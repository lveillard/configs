import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tomllib
import urllib.error
import urllib.request

home=Path.home(); root=home/'.config/dev-profiles'; profiles=json.loads((root/'profiles.json').read_text())
secrets=json.loads((root/'secrets.json').read_text())
assert root.stat().st_mode & 0o077 == 0
private_files=[root/'secrets.json',root/'profiles.json',root/'aws/config']
for name in profiles['profiles']:
    private_files.extend(p for p in (root/name).glob('*') if p.is_file())
for p in private_files:
    if p.stat().st_mode & 0o077: raise SystemExit('Non-private profile file: '+str(p))
for name in ('codex','codex-work','codex-personal','claude','claude-work','claude-personal'):
    assert not (root/name/'auth.json').exists()
    assert not (root/name/'.credentials.json').exists()
for name in profiles['profiles']:
    for p in (root/name).glob('*.toml'): tomllib.loads(p.read_text())
print('Private permissions, TOML parsing and OAuth exclusion: OK',flush=True)

original_exec=os.execve; original_argv=sys.argv[:]; original_env=os.environ.copy()
class Captured(Exception): pass
captured={}
def capture(binary,args,env):
    captured.update(binary=binary,args=args,env=env)
    raise Captured()
try:
    os.execve=capture
    os.environ.update(OPENAI_API_KEY='test-unrelated',ANTHROPIC_API_KEY='test-unrelated',CODEX_HOME='/tmp/test-unrelated')
    for name,profile in profiles['profiles'].items():
        captured.clear(); sys.argv=[str(home/'.local/bin/dev-profile'),name,'--version']
        try: runpy.run_path(str(home/'.config/dev-terminal/dev-profile'),run_name='__main__')
        except Captured: pass
        env=captured['env']
        assert env.get('HOME')==original_env.get('HOME')
        assert env.get('OPENAI_API_KEY')!='test-unrelated' and env.get('ANTHROPIC_API_KEY')!='test-unrelated'
        for k,v in profile.get('env',{}).items(): assert env[k]==v
        for k,v in secrets.get(profile.get('secrets'),{}).items(): assert env[k]==v
    print('All 20 alias environments and credential isolation: OK',flush=True)
finally:
    os.execve=original_exec; sys.argv=original_argv; os.environ.clear(); os.environ.update(original_env)

def models(label,url,key):
    request=urllib.request.Request(url,headers={'Authorization':'Bearer '+key,'Accept':'application/json'})
    try:
        with urllib.request.urlopen(request,timeout=25) as response:
            data=response.read()
            print(label+': HTTP '+str(response.status),flush=True)
    except urllib.error.HTTPError as error: print(label+': HTTP '+str(error.code),flush=True)
    except Exception as error: print(label+': '+type(error).__name__,flush=True)
models('Azure Foundry','https://eastus.api.cognitive.microsoft.com/openai/v1/models',secrets['codex-api']['AZURE_OPENAI_API_KEY'])
for group in ('grok','grok-api'):
    config=tomllib.loads((root/group/'config.toml').read_text())
    qwen=config.get('model',{}).get('qwen38')
    if qwen and qwen.get('env_key') in secrets[group]:
        models(group+' Qwen',qwen['base_url'].rstrip('/')+'/models',secrets[group][qwen['env_key']])
auth=json.loads((root/'pi/auth.json').read_text())
models('DeepSeek','https://api.deepseek.com/models',auth['deepseek']['key'])
result=subprocess.run([str(home/'.local/bin/codex-api'),'features','list'],capture_output=True,text=True,timeout=30)
print('Codex API configuration: '+('OK' if result.returncode==0 else 'FAILED'),flush=True)
assert result.returncode==0
print('Verification completed.',flush=True)

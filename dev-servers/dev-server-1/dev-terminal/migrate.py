"""Copy portable configs and API keys over SSH stdin. Never print credential data."""
import io
import json
import os
from pathlib import Path, PurePosixPath
import shlex
import subprocess
import tarfile
import tomllib

LOCAL=Path.home()
SOURCE=Path(__file__).parent
REMOTE='/home/devuser'
BASE=REMOTE+'/.config/dev-profiles'
TOOLS=REMOTE+'/.local/share/dev-tools'
files={}
def put(path,data,mode=0o600):
    files[path]=(data.encode() if isinstance(data,str) else data,mode)
def js(path,data): put(path,json.dumps(data,ensure_ascii=False,indent=2)+'\n')
def readjson(path): return json.loads(path.read_text(encoding='utf-8-sig'))
def readtoml(path): return tomllib.loads(path.read_text(encoding='utf-8-sig')) if path.exists() else {}
def toml(data,prefix=()):
    result=[]
    if prefix: result.append('['+'.'.join(json.dumps(x) for x in prefix)+']')
    for k,v in data.items():
        if not isinstance(v,dict): result.append(json.dumps(k)+' = '+json.dumps(v,ensure_ascii=False))
    for k,v in data.items():
        if isinstance(v,dict): result += ['',toml(v,prefix+(k,))]
    return '\n'.join(result)+'\n'

profiles={}
secrets={}
executables={'codex':TOOLS+'/npm/bin/codex','pi':TOOLS+'/npm/bin/pi','pi-13':TOOLS+'/pi-1.3/node_modules/.bin/pi','pi-plus-13':TOOLS+'/pi-plus-1.3/node_modules/.bin/pi','gemini':TOOLS+'/npm/bin/gemini','claude':TOOLS+'/claude','devin':TOOLS+'/devin/bin/devin','grok':TOOLS+'/grok'}
def profile(name,engine,env=None,secret=None,args=None):
    profiles[name]={'engine':engine,'env':env or {}}
    if secret: profiles[name]['secrets']=secret
    if args: profiles[name]['args']=args

for name,source in [('codex','.codex'),('codex-work','.project-a-cli/codex'),('codex-personal','.personal-cli/codex')]:
    data=readtoml(LOCAL/source/'config.toml')
    data={k:v for k,v in data.items() if k in ('model','model_reasoning_effort','model_context_window') and isinstance(v,(str,int))}
    data['cli_auth_credentials_store']='file'
    put(f'.config/dev-profiles/{name}/config.toml',toml(data))
    profile(name,'codex',{'CODEX_HOME':BASE+'/'+name})
data=readtoml(LOCAL/'.codex-azure/config.toml')
portable={k:data[k] for k in ('model','model_provider','model_reasoning_effort','model_context_window') if k in data}
azure=data['model_providers']['azure']
portable['model_providers']={'azure':{k:azure[k] for k in ('name','base_url','env_key','wire_api') if k in azure}}
portable['profiles']={}
for model in ('astra','sol','terra','luna'):
    source=readtoml(LOCAL/f'.codex-azure/{model}.config.toml')
    portable['profiles'][model]={k:source[k] for k in ('model','model_provider','model_reasoning_effort','model_context_window') if k in source}
put('.config/dev-profiles/codex-api/config.toml',toml(portable))
foundry=(LOCAL/'.grok-azure/foundry.key').read_text().strip()
assert foundry
secrets['codex-api']={'AZURE_OPENAI_API_KEY':foundry}
profile('codex-api','codex',{'CODEX_HOME':BASE+'/codex-api'},'codex-api')

for name,source in [('claude','.claude'),('claude-work','.project-a-cli/claude'),('claude-personal','.claude-split/personal/.claude')]:
    p=LOCAL/source/'settings.json'
    data=readjson(p) if p.exists() else {}
    data={k:v for k,v in data.items() if k in ('model','availableModels','alwaysThinkingEnabled','effortLevel','language')}
    js(f'.config/dev-profiles/{name}/settings.json',data)
    profile(name,'claude',{'CLAUDE_CONFIG_DIR':BASE+'/'+name})
js('.config/dev-profiles/claude-bedrock/settings.json',readjson(LOCAL/'.claude/bedrock-settings.json'))
for name,scope,region,tier in [('claude-api','eu','eu-west-1','opus'),('claude-api-global','global','eu-west-1','opus'),('claude-api-eu2','eu','eu-central-1','opus'),('claude-api-global-eu2','global','eu-central-1','opus'),('claude-api-sonnet','eu','eu-west-1','sonnet')]:
    env={'CLAUDE_CONFIG_DIR':BASE+'/claude-bedrock','CLAUDE_CODE_USE_BEDROCK':'1','AWS_PROFILE':'claude-api','AWS_CONFIG_FILE':BASE+'/aws/config','AWS_SHARED_CREDENTIALS_FILE':BASE+'/aws/credentials','AWS_REGION':region,'AWS_DEFAULT_REGION':region,'ANTHROPIC_SMALL_FAST_MODEL_AWS_REGION':region,'ANTHROPIC_MODEL':tier,'ANTHROPIC_DEFAULT_OPUS_MODEL':scope+'.anthropic.claude-opus-4-6-v1','ANTHROPIC_DEFAULT_SONNET_MODEL':scope+'.anthropic.claude-sonnet-4-6','ANTHROPIC_DEFAULT_HAIKU_MODEL':scope+'.anthropic.claude-haiku-4-5-20251001-v1:0'}
    profile(name,'claude',env)
aws=(LOCAL/'.aws/config').read_text().replace('credential_process = aws ','credential_process = '+TOOLS+'/aws-bin/aws ')
put('.config/dev-profiles/aws/config',aws)

for name,source in [('grok','.grok'),('grok-api','.grok-azure')]:
    original=readtoml(LOCAL/source/'config.toml')
    config={'cli':{'installer':'internal'},'model':original.get('model',{})}
    group={}
    for model,settings in config['model'].items():
        if not isinstance(settings,dict): continue
        if 'api_key' in settings:
            var='DEV_GROK_'+''.join(c if c.isalnum() else '_' for c in model.upper())+'_API_KEY'
            group[var]=settings.pop('api_key'); settings['env_key']=var
        var=settings.get('env_key')
        if var and var not in group:
            value=foundry if name=='grok-api' and var=='XAI_API_KEY' else os.environ.get(var)
            if value: group[var]=value
    env={'GROK_HOME':BASE+'/'+name}
    # Reuse a local credential only when the configured provider endpoint matches.
    if name=='grok-api':
        current=readtoml(LOCAL/'.grok/config.toml').get('model',{}).get('qwen38',{})
        current_var=current.get('env_key','DEV_GROK_QWEN38_API_KEY')
        if current_var in secrets.get('grok',{}) and current.get('base_url')==config['model'].get('qwen38',{}).get('base_url'):
            group[config['model']['qwen38']['env_key']]=secrets['grok'][current_var]
    if name=='grok-api': env.update(GROK_MODELS_BASE_URL='https://eastus.api.cognitive.microsoft.com/openai/v1',GROK_DEFAULT_MODEL='grok-4-6')
    secrets[name]=group
    put(f'.config/dev-profiles/{name}/config.toml',toml(config))
    profile(name,'grok',env,name if group else None)
profile('grok-qwen','grok',profiles['grok']['env'],profiles['grok'].get('secrets'),['--model','qwen38'])

for name,source in [('pi','agent'),('pi-plus','agent-plus'),('pi-plus-jev','agent-plus-jev')]:
    local=LOCAL/'.pi'/source
    settings=readjson(local/'settings.json')
    settings={k:v for k,v in settings.items() if k in ('defaultProvider','defaultModel','defaultThinkingLevel','enabledModels','compaction','packages','theme','hideThinkingBlock')}
    packages=[]
    for package in settings.get('packages',[]):
        if isinstance(package,str):
            if package.startswith('npm:'): packages.append(package)
            elif 'pi-session-ledger' in package: packages.append(TOOLS+'/extensions/pi-session-ledger')
            elif 'pi-fast-jev-compaction' in package: packages.append(TOOLS+'/extensions/pi-fast-jev-compaction')
    settings['packages']=packages
    settings['sessionDir']=BASE+('/pi/sessions' if name in ('pi','pi-plus') else '/pi-plus-jev/sessions')
    js(f'.config/dev-profiles/{name}/settings.json',settings)
    models=readjson(local/'models.json')
    js(f'.config/dev-profiles/{name}/models.json',models)
    auth=readjson(local/'auth.json')
    auth={k:v for k,v in auth.items() if isinstance(v,dict) and v.get('type')=='api_key'}
    js(f'.config/dev-profiles/{name}/auth.json',auth)
    env={'PI_CODING_AGENT_DIR':BASE+'/'+name}
    if name=='pi-plus-jev':
        env.update(PI_JEV_MODEL='jev-1.13.0',PI_JEV_DIAGNOSTICS_FILE=BASE+'/pi-plus-jev/logs/fast-jev-compaction.jsonl')
    profile(name,{'pi':'pi-13','pi-plus':'pi-plus-13','pi-plus-jev':'pi'}[name],env,'pi-plus-jev' if name=='pi-plus-jev' else None)

# DPAPI is decoded locally; captured bytes go straight into the encrypted SSH stream.
script="$ErrorActionPreference='Stop'; $s=ConvertTo-SecureString (Get-Content -LiteralPath (Join-Path $env:USERPROFILE '.pi/agent-plus-jev/typesafe-key.dpapi') -Raw).Trim(); [Console]::Write([System.Net.NetworkCredential]::new('', $s).Password)"
result=subprocess.run([r'C:\Program Files\PowerShell\7\pwsh.exe','-NoProfile','-NonInteractive','-Command',script],capture_output=True)
if result.returncode: raise SystemExit('Could not decrypt the local Jev API key; no credential output was logged.')
key=result.stdout.decode().strip()
assert key
secrets['pi-plus-jev']={'TYPESAFE_API_KEY':key}
profile('devin','devin')
profile('gemini','gemini',{'NO_BROWSER':'true'})

for project,dirs,rootfiles in [('pi-session-ledger',['src','skills'],['package.json','index.ts','question.ts','README.md']),('pi-fast-jev-compaction',['extensions'],['package.json','LICENSE','THIRD_PARTY_LICENSES.md','README.md'])]:
    source=LOCAL/'Desktop/Projects'/project
    selected=[source/f for f in rootfiles if (source/f).is_file()]
    for directory in dirs:
        selected += [p for p in (source/directory).rglob('*') if p.is_file() and p.suffix in ('.ts','.md','.json') and not p.name.endswith('.test.ts')]
    for p in selected: put('.local/share/dev-tools/extensions/'+project+'/'+p.relative_to(source).as_posix(),p.read_bytes())

js('.config/dev-profiles/profiles.json',{'executables':executables,'profiles':profiles})
js('.config/dev-profiles/secrets.json',secrets)
for name in ('dev','dev-actions','dev-profile','dev-shell','session-shell','tmux.conf','starship.toml','dev-login'):
    p=SOURCE/name
    if p.exists(): put('.config/dev-terminal/'+name,p.read_bytes().replace(b'\r\n',b'\n'),0o700 if '.' not in name else 0o600)
put('.config/dev-terminal/zsh/.zshrc',(SOURCE/'zsh/.zshrc').read_bytes().replace(b'\r\n',b'\n'))

receiver='''import io,os,pathlib,sys,tarfile
os.umask(0o077)
root=pathlib.Path.home()
allowed=('.config/dev-terminal/','.config/dev-profiles/','.local/share/dev-tools/extensions/')
with tarfile.open(fileobj=sys.stdin.buffer,mode='r|') as archive:
 for member in archive:
  if not member.isfile() or not member.name.startswith(allowed) or '..' in pathlib.PurePosixPath(member.name).parts: raise SystemExit('Invalid migration path')
  target=root/member.name
  if not target.resolve().is_relative_to(root): raise SystemExit('Invalid migration target')
  target.parent.mkdir(parents=True,exist_ok=True)
  target.write_bytes(archive.extractfile(member).read())
  target.chmod(member.mode)
print('Portable settings and API credentials transferred privately; OAuth caches excluded.')
'''
buffer=io.BytesIO()
with tarfile.open(fileobj=buffer,mode='w') as archive:
    for path,(data,mode) in files.items():
        item=tarfile.TarInfo(path); item.size=len(data); item.mode=mode
        archive.addfile(item,io.BytesIO(data))
result=subprocess.run(['ssh','-T','-o','BatchMode=yes','dev-server-1','python3 -c '+shlex.quote(receiver)],input=buffer.getvalue(),capture_output=True)
if result.returncode: raise SystemExit('Migration failed. Credential-containing stderr suppressed; inspect the receiver without dumping data.')
print(result.stdout.decode().strip())
print('Profiles:',', '.join(profiles))

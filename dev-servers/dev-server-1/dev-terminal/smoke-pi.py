import json
import os
from pathlib import Path
import selectors
import subprocess
import tempfile
import time

root=Path.home()/'.config/dev-profiles'
workspace=Path.home()/'.local/state/dev-terminal/smoke'
workspace.mkdir(exist_ok=True)
env=os.environ.copy(); env['PATH']=str(Path.home()/'.local/bin')+':'+env['PATH']
for name in ('pi','pi-plus','pi-plus-jev'):
    # The latest Pi catalogue renamed the old DeepSeek Flash model ID.
    p=root/name/'settings.json'; settings=json.loads(p.read_text())
    if settings.get('defaultModel')=='deepseek-flash': settings['defaultModel']='deepseek-v4-flash'
    settings['enabledModels']=['deepseek-v4-flash' if x=='deepseek-flash' else x for x in settings.get('enabledModels',[])]
    p.write_text(json.dumps(settings,indent=2)+'\n'); p.chmod(0o600)
    p=root/name/'models.json'; models=json.loads(p.read_text())
    overrides=models.get('providers',{}).get('deepseek',{}).get('modelOverrides',{})
    if 'deepseek-flash' in overrides: overrides['deepseek-v4-flash']=overrides.pop('deepseek-flash')
    p.write_text(json.dumps(models,indent=2)+'\n'); p.chmod(0o600)
    with tempfile.TemporaryFile() as stderr:
        proc=subprocess.Popen([str(Path.home()/'.local/bin'/name),'--mode','rpc','--no-session','--no-approve'],cwd=workspace,env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=stderr)
        proc.stdin.write(b'{"id":"state","type":"get_state"}\n{"id":"commands","type":"get_commands"}\n'); proc.stdin.flush()
        selector=selectors.DefaultSelector(); selector.register(proc.stdout,selectors.EVENT_READ)
        found={}; errors=[]; buffer=b''; deadline=time.monotonic()+40
        try:
            while len(found)<2 and time.monotonic()<deadline:
                for key,_ in selector.select(timeout=.5):
                    chunk=os.read(key.fileobj.fileno(),65536)
                    if not chunk: break
                    buffer+=chunk
                    while b'\n' in buffer:
                        line,buffer=buffer.split(b'\n',1)
                        try: item=json.loads(line)
                        except ValueError: continue
                        if item.get('type')=='extension_error': errors.append(item.get('extensionPath','unknown extension'))
                        if item.get('id') in ('state','commands'): found[item['id']]=item
                if proc.poll() is not None: break
        finally:
            proc.terminate()
            try: proc.wait(timeout=5)
            except subprocess.TimeoutExpired: proc.kill(); proc.wait()
            selector.close()
        stderr.seek(0); diagnostics=stderr.read().decode(errors='replace')
        failed=any(x in diagnostics.lower() for x in ('failed to load extension','cannot find module','error loading extension'))
        ok=len(found)==2 and all(x.get('success') for x in found.values()) and not errors and not failed
        commands=found.get('commands',{}).get('data',{}).get('commands',[])
        names=[c['name'] for c in commands]
        custom=[x for x in names if 'ledger' in x or 'jev' in x]
        print(name+': '+('OK' if ok else 'FAILED')+'; registered custom commands: '+', '.join(custom),flush=True)
        if not ok:
            # Redact every known API credential before reporting a bounded diagnostic.
            secret_values=[v for group in json.loads((root/'secrets.json').read_text()).values() for v in group.values()]
            secret_values += [v.get('key','') for v in json.loads((root/name/'auth.json').read_text()).values()]
            for value in secret_values:
                if value: diagnostics=diagnostics.replace(value,'[REDACTED]')
            print(diagnostics[-2000:])
            raise SystemExit(1)
print('Pi RPC startup and local extensions verified without sending model prompts.',flush=True)

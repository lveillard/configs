import json
import os
from pathlib import Path
import subprocess

os.umask(0o077)
home=Path.home(); root=home/'.config/dev-terminal'; tools=home/'.local/share/dev-tools'; bin=home/'.local/bin'
profiles=json.loads((home/'.config/dev-profiles/profiles.json').read_text())['profiles']
links={name:root/'dev-profile' for name in profiles}
links.update({name:root/name for name in ('dev','dev-profile','dev-login','dev-shell')})
links.update({name:tools/'node/bin'/name for name in ('node','npm','npx')})
links.update(aws=tools/'aws-bin/aws',starship=tools/'starship-bin/starship')
for name,target in links.items():
    p=bin/name
    if (p.exists() or p.is_symlink()) and not (p.is_symlink() and p.resolve()==target.resolve()):
        raise SystemExit('Existing command preserved; resolve conflict before continuing: '+name)
for name,target in links.items():
    p=bin/name
    if not p.is_symlink(): p.symlink_to(target)
for name in profiles:
    (home/'.config/dev-profiles'/name).mkdir(exist_ok=True)
for path in (home/'.local/state/dev-terminal',home/'.config/dev-profiles/pi/sessions',home/'.config/dev-profiles/pi-plus-jev/sessions',home/'.config/dev-profiles/pi-plus-jev/logs'):
    path.mkdir(parents=True,exist_ok=True)
for p in (home/'.config/dev-profiles').rglob('*'):
    p.chmod(0o700 if p.is_dir() else 0o600)
env=os.environ.copy(); env['PATH']=str(bin)+':'+str(tools/'node/bin')+':'+env['PATH']
subprocess.run(['npm','rebuild','--global','--prefix',str(tools/'npm'),'--allow-scripts=@github/keytar,node-pty,@google/genai,esbuild,protobufjs'],env=env,check=True)
for name in ('codex','claude','grok','devin','pi','gemini'):
    result=subprocess.run([str(bin/name),'--version'],env=env,capture_output=True,text=True,timeout=45)
    # Versions only. Never dump arbitrary diagnostics from a tool carrying credentials.
    lines=[line for line in result.stdout.splitlines() if line.strip()]
    print(name+': '+(lines[-1] if result.returncode==0 and lines else 'FAILED (diagnostics withheld)'),flush=True)
    if result.returncode: raise SystemExit('Version check failed for '+name)
print('Installed aliases and isolated profiles.',flush=True)

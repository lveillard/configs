import json
import os
from pathlib import Path
import subprocess

home=Path.home()
env=os.environ.copy(); env['PATH']=str(home/'.local/bin')+':'+env['PATH']
os.chdir(home)
for name in ('pi','pi-plus','pi-plus-jev'):
    settings=json.loads((home/'.config/dev-profiles'/name/'settings.json').read_text())
    for package in settings['packages']:
        if not package.startswith('npm:'): continue
        print(name+': installing '+package,flush=True)
        result=subprocess.run([str(home/'.local/bin'/name),'install',package,'--no-approve'],env=env,capture_output=True,text=True,timeout=240)
        if result.returncode:
            # Installers are invoked with profile credentials; keep raw diagnostics private.
            log=home/'.local/state/dev-terminal'/('install-'+name+'.log')
            log.write_text(result.stdout+result.stderr); log.chmod(0o600)
            raise SystemExit('Package installation failed; private diagnostic file: '+str(log))
print('All Pi packages installed.',flush=True)

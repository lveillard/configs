#!/usr/bin/env bash
set -euo pipefail
umask 077
sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get update -qq
sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get install -y -qq zsh fzf zsh-autosuggestions zsh-syntax-highlighting unzip
mkdir -p "$HOME/.local/share/dev-tools" "$HOME/.local/bin" "$HOME/.config/dev-terminal" "$HOME/.config/dev-profiles"
chmod 700 "$HOME/.config/dev-profiles"
python3 - <<'PY'
import hashlib, json, os, pathlib, subprocess, tarfile, urllib.request, zipfile
root=pathlib.Path.home()/'.local/share/dev-tools'
downloads=root/'downloads'; downloads.mkdir(exist_ok=True)
def get(url):
    with urllib.request.urlopen(url,timeout=90) as r: return r.read()
def download(url,name,sha=None):
    p=downloads/name
    if not p.exists():
        print('Downloading '+name,flush=True)
        with urllib.request.urlopen(url,timeout=180) as r, p.open('wb') as f:
            while data:=r.read(1024*1024): f.write(data)
    if sha and hashlib.file_digest(p.open('rb'),'sha256').hexdigest()!=sha:
        p.unlink(); raise SystemExit('Checksum mismatch: '+name)
    return p
def untar(p,target):
    target.mkdir(exist_ok=True,parents=True)
    with tarfile.open(p) as t: t.extractall(target,filter='data')
versions={}
node=next(x for x in json.loads(get('https://nodejs.org/dist/index.json')) if x['lts'])['version']
archive=f'node-{node}-linux-x64.tar.xz'
base=f'https://nodejs.org/dist/{node}/'
sha=next(x.split()[0] for x in get(base+'SHASUMS256.txt').decode().splitlines() if x.endswith('  '+archive))
untar(download(base+archive,archive,sha),root)
link=root/'node'
if link.is_symlink(): link.unlink()
link.symlink_to(root/f'node-{node}-linux-x64')
versions['node']=node
env=os.environ.copy(); env['PATH']=str(link/'bin')+':'+env['PATH']
packages=['@openai/codex','@earendil-works/pi-coding-agent','@google/gemini-cli']
specs=[]
for package in packages:
    version=json.loads(get('https://registry.npmjs.org/'+package+'/latest'))['version']
    versions[package]=version; specs.append(package+'@'+version)
subprocess.run(['npm','install','--global','--prefix',str(root/'npm'),'--no-audit','--no-fund',*specs],env=env,check=True)
base='https://downloads.claude.ai/claude-code-releases'
version=get(base+'/latest').decode().strip()
manifest=json.loads(get(f'{base}/{version}/manifest.json'))
p=download(f'{base}/{version}/linux-x64/claude','claude-'+version,manifest['platforms']['linux-x64']['checksum'])
p.chmod(0o700); (root/'claude').unlink(missing_ok=True); (root/'claude').symlink_to(p)
versions['claude']=version
manifest=json.loads(get('https://static.devin.ai/cli/current/manifest.json'))
# The public manifest keys are read below and checked against its platform hash.
platform=manifest['platforms']['x86_64-unknown-linux']
version=manifest['version']
p=download(platform['url'],'devin-'+version+'.tar.gz',platform['sha256'])
untar(p,root/'devin'); versions['devin']=version
base='https://x.ai/cli'
version=get(base+'/stable').decode().strip()
p=download(f'{base}/grok-{version}-linux-x86_64','grok-'+version)
p.chmod(0o700); subprocess.run([str(p),'--version'],check=True)
(root/'grok').unlink(missing_ok=True); (root/'grok').symlink_to(p)
versions['grok']=version
archive='starship-x86_64-unknown-linux-musl.tar.gz'
release=json.loads(get('https://api.github.com/repos/starship/starship/releases/latest'))
base='https://github.com/starship/starship/releases/download/'+release['tag_name']+'/'
sha=get(base+archive+'.sha256').decode().split()[0]
untar(download(base+archive,archive,sha),root/'starship-bin')
versions['starship']=release['tag_name']
p=download('https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip','awscliv2.zip')
with zipfile.ZipFile(p) as z: z.extractall(root/'aws-install')
for p in (root/'aws-install/aws').rglob('*'):
    if p.is_file(): p.chmod(0o700)
subprocess.run([str(root/'aws-install/aws/install'),'--install-dir',str(root/'aws-cli'),'--bin-dir',str(root/'aws-bin'),'--update'],check=True)
(root/'versions.json').write_text(json.dumps(versions,indent=2)+'\n')
print(json.dumps(versions,indent=2),flush=True)
PY

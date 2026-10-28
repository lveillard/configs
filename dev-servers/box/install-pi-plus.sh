#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.local/share/dev-tools/node/bin:$PATH"
version=${PI_VERSION:-1.3.0}
npm uninstall -g @mariozechner/pi-coding-agent >/dev/null 2>&1 || true
[ -L "$HOME/.local/bin/pi" ] && unlink "$HOME/.local/bin/pi"
dir="$HOME/.local/share/dev-tools/pi-plus-$version"
ext="$HOME/.local/share/dev-tools/extensions/pi-session-ledger"
mkdir -p "$dir" "$HOME/.config/pi-plus/sessions" "$ext"
chmod 700 "$HOME/.config/pi-plus"
npm install --prefix "$dir" --no-audit --no-fund "@earendil-works/pi-coding-agent@$version" >/dev/null
install -m 600 /tmp/pi-plus-settings.json "$HOME/.config/pi-plus/settings.json"
install -m 600 /tmp/pi-plus-models.json "$HOME/.config/pi-plus/models.json"
install -m 755 /tmp/pi-plus "$HOME/.local/bin/pi-plus"
# The ledger is a copy of the local checkout, refreshed only by this installer.
[ -f /tmp/pi-session-ledger.tgz ] && tar xzf /tmp/pi-session-ledger.tgz -C "$ext"
python3 - "$HOME/.config/pi-plus/settings.json" "$ext" <<'PY'
import json, os, sys
path, package = sys.argv[1], sys.argv[2]
with open(path) as handle:
    settings = json.load(handle)
packages = settings.setdefault("packages", [])
def resolved(value):
    return os.path.realpath(os.path.join(os.path.dirname(path), value))
if not any(resolved(value) == resolved(package) for value in packages):
    packages.append(package)
with open(path, "w") as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")
PY
for p in $(python3 -c 'import json,os; print(" ".join(json.load(open(os.path.expanduser("~/.config/pi-plus/settings.json")))["packages"]))'); do
  pi-plus install "$p" --no-approve >/dev/null 2>&1 || pi-plus install "$p" >/dev/null
done
echo "pi-plus $(pi-plus --version)"; pi-plus list 2>&1 | head -12
command -v pi || echo "no plain pi"

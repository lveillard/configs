#!/usr/bin/env bash
# Run after `terraform apply` and cloud-init for a box listed in boxes.json:
#   bash finish.sh dev-server-project-a
# Installs the pinned WezTerm mux (kept out of needrestart so updates never kill sessions), zsh/atuin/starship, tmux + `t`, pi-plus, and enables Tailscale SSH.
# Safe to rerun: it never restarts a running mux, so open sessions survive. No cloud CLIs by design.
set -euo pipefail
box=${1:?usage: finish.sh <box name>}
here=$(cd "$(dirname "$0")" && pwd)
read -r label color profiles < <(python -I -c "
import json,sys
b=[b for b in json.load(open(sys.argv[1]))['boxes'] if b['name']==sys.argv[2]][0]
print(b['label'], (b.get('tint') or {}).get('tmux','#2e3440'), ','.join(b.get('claudeProfiles') or []))" "$here/boxes.json" "$box" | tr -d '\r')
deb="$HOME/.local/share/dev-servers/wezterm-nightly_20260917-114457-b09b56c2_amd64.deb"
sum=40d6305d0b0c12b72eddfa0e42abc497d18790bb1024a34c5f784ba583a1df73
S=/c/Windows/System32/OpenSSH
tmp=$(mktemp -d)
# claude-<name> wrappers listed under claudeProfiles in boxes.json.
links=""
for p in ${profiles//,/ }; do links+=" && ln -sfn claude-profile ~/.local/bin/$p"; done
sed "s/__LABEL__/$label/; s/__COLOR__/$color/" "$here/box/tmux.conf" > "$tmp/tmux.conf"
"$S/scp.exe" -q "$(cygpath -w "$deb")" "$box:/tmp/wezterm.deb"
"$S/scp.exe" -q "$(cygpath -w "$tmp/tmux.conf")" "$box:/tmp/tmux.conf"
for f in t claude-profile 99-wezterm-preserve-sessions.conf pi-plus install-pi-plus.sh pi-plus-settings.json pi-plus-models.json smoke-pi-plus.py zshenv zshrc atuin.toml starship.toml install-zsh.sh; do
  source="$here/box/$f"
  [ ! -f "$here/box/overrides/$box/$f" ] || source="$here/box/overrides/$box/$f"
  "$S/scp.exe" -q "$(cygpath -w "$source")" "$box:/tmp/$f"
done
ledger="$HOME/Desktop/Projects/pi-session-ledger"
tar czf "$tmp/pi-session-ledger.tgz" -C "$ledger" package.json index.ts question.ts README.md src skills
"$S/scp.exe" -q "$(cygpath -w "$tmp/pi-session-ledger.tgz")" "$box:/tmp/pi-session-ledger.tgz"
"$S/ssh.exe" "$box" "echo '$sum  /tmp/wezterm.deb' | sha256sum -c - >/dev/null \
  && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q /tmp/wezterm.deb >/dev/null 2>&1 \
  && sudo install -m 644 /tmp/99-wezterm-preserve-sessions.conf /etc/needrestart/conf.d/ \
  && (systemctl is-active --quiet wezterm-mux.service || sudo systemctl start wezterm-mux.service) \
  && install -m 644 /tmp/tmux.conf ~/.tmux.conf && install -m 755 /tmp/t ~/.local/bin/t \
  && install -m 755 /tmp/claude-profile ~/.local/bin/claude-profile \
  $links \
  && bash /tmp/install-pi-plus.sh 2>&1 | grep -E '^pi-plus|no plain' \
  && python3 /tmp/smoke-pi-plus.py pi-plus 2>&1 | tail -3 \
  && bash /tmp/install-zsh.sh $label | tail -2 \
  && sudo tailscale set --ssh && hostname && systemctl is-active wezterm-mux.service docker earlyoom tailscaled"

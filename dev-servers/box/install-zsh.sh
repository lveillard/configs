#!/usr/bin/env bash
# zsh + atuin + starship for the login user; makes zsh the shell for SSH, tmux and the WezTerm mux.
set -euo pipefail
label=${1:?label}
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq zsh fzf zsh-autosuggestions zsh-syntax-highlighting >/dev/null
mkdir -p "$HOME/.local/bin" "$HOME/.local/state/zsh" "$HOME/.config/atuin"
printf '%s\n' "$label" > "$HOME/.config/box-label"
[ -x "$HOME/.local/bin/starship" ] || curl -fsSL https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin" >/dev/null
if [ ! -x "$HOME/.atuin/bin/atuin" ]; then
  # Release asset by fixed URL plus its published checksum (the installer needs GitHub's rate-limited API).
  a=atuin-x86_64-unknown-linux-gnu; b=https://github.com/atuinsh/atuin/releases/latest/download
  (cd /tmp && curl -fsSLO "$b/$a.tar.gz" && curl -fsSLO "$b/$a.tar.gz.sha256"     && [ "$(cut -d' ' -f1 "$a.tar.gz.sha256")" = "$(sha256sum "$a.tar.gz" | cut -d' ' -f1)" ]     && tar -xzf "$a.tar.gz" && install -D -m 755 "$a/atuin" "$HOME/.atuin/bin/atuin")
fi
install -m 644 /tmp/zshrc "$HOME/.zshrc"
install -m 644 /tmp/atuin.toml "$HOME/.config/atuin/config.toml"
install -m 644 /tmp/starship.toml "$HOME/.config/starship.toml"
install -m 644 /tmp/zshenv "$HOME/.zshenv"
sudo usermod -s /usr/bin/zsh "$USER"
# New WezTerm panes and tmux windows start zsh.
sudo sed -i "s#default_prog = { '/bin/bash', '-l' }#default_prog = { '/usr/bin/zsh', '-l' }#" /etc/wezterm/wezterm.lua
tmux source-file "$HOME/.tmux.conf" 2>/dev/null || true
"$HOME/.atuin/bin/atuin" import bash >/dev/null 2>&1 || true
echo "$(hostname): $(getent passwd "$USER" | cut -d: -f7), $(zsh --version | cut -d' ' -f1-2), atuin $("$HOME/.atuin/bin/atuin" --version | cut -d' ' -f2), starship $("$HOME/.local/bin/starship" --version | head -1 | cut -d' ' -f2), mux prog: $(grep -o "default_prog = {[^}]*}" /etc/wezterm/wezterm.lua)"
zsh -ic 'echo zshrc-loads-ok' 2>&1 | tail -1

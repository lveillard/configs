# Dev servers

One Azure VM per project. Copy [`boxes.example.json`](boxes.example.json) to
`boxes.json`, then enter your own VM names, subscription IDs, Tailscale domain and
user settings. Every shared tool reads this local inventory; Git ignores it.
The committed inventory contains examples only.

| Path | What it is |
| --- | --- |
| `launcher/launch.ps1 -Box <name>` | Opens WezTerm Remote over Tailscale (starts a stopped VM if needed). `-CheckOnly` tests it. |
| `launcher/install-shortcuts.ps1` | Desktop/Start shortcuts and `wezterm-rem[-label]` commands for every box. |
| `launcher/wezterm.lua`, `sessions.lua` | Shared WezTerm config and session manager (Ctrl+Shift+S, Ctrl+Shift+A). |
| `infra/` | Terraform, one workspace per box (`terraform workspace select <name>`). State stays local. |
| `finish.sh <name>` | After apply: WezTerm mux, zsh/atuin/starship, tmux + `t`, pi-plus, Tailscale SSH. Safe to rerun. |
| `box/` | Files `finish.sh` installs on the box. |
| `box/overrides/<box>/` | Per-box files that replace the corresponding shared file during `finish.sh`. |
| `tests/check-create-once.py <name>` | Drives a test window to check session creation end to end. |
| `dev-server-1/` | Standalone agent wrappers and the optional tmux-based `dev-terminal` interface. |

See [How sessions work](SESSIONS.md) for the complete control path, the actual
session-manager source, agent commands, and disconnect/restart semantics.

## Add a box

```bash
# From dev-servers/:
cp boxes.example.json boxes.json
# 1. Add an entry to boxes.json (name, label, subscription, resource group, tint, terraform block).
# 2. Key, VM, finish:
ssh-keygen -t ed25519 -N "" -f ~/.ssh/<name>_ed25519
cd infra
terraform init
terraform workspace new <name>
terraform apply -var ssh_source_ip=$(curl -s https://api.ipify.org)
cd ..
# 3. Use the public IP locally for bootstrap; pin the verified host key in
# ~/.ssh/<name>_known_hosts and add a Host entry to ~/.ssh/config.
# After joining Tailscale, use the box's Tailscale hostname in that Host entry.
bash finish.sh <name>
# 4. Once Tailscale SSH works, close public SSH again:
cd infra
terraform apply -var ssh_source_ip=
cd ..
pwsh -File launcher/install-shortcuts.ps1
```

Not in git: credentials (`auth.json`, logins), Terraform state, and the pinned WezTerm
package (`~/.local/share/dev-servers/`). Dev boxes never get `az`, `aws` or cloud credentials.

Edit all example paths and local inventory values before use. `finish.sh` runs from Git Bash on
Windows, needs the pinned WezTerm package and a local `pi-session-ledger` checkout,
and installs packages/configuration on the remote machine. It does not install the
original VM's `agent-spawn`/`agent-kill`; their manual install is in the session guide.

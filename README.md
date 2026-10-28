# configs

Public examples of the WezTerm session manager, VM tooling and Pi configuration.
VM names, network settings, account aliases and user paths in this repository are
examples. Real infrastructure inventories, credentials and operational history are
kept separately in private storage.

Windows dotfiles: WezTerm and Pi agent settings. `~/.wezterm.lua` is a hardlink to
`wezterm/wezterm.lua`, so edits to either path update the same file. Pi configuration
lives in [`pi/`](pi/README.md) and is installed with `pi/sync.ps1`; it is not hardlinked
because Pi rewrites those files.

## Current setup

- Integrated GPU preference: DX12, then Vulkan, with software rendering as a fallback.
  GPU discovery is cached for the process lifetime, including color-driven config reloads.
- Fixed 96 DPI, with font sizing for the laptop and external displays.
- Account colors for Claude, Codex, and Grok, including the Azure Codex profile.
- Conversation titles from terminal title updates, with manual overrides and per-tab state.
  An inactive tab or split exiting cannot clear the active conversation's title.
- Right-click appearance menu, opacity toggle, prompt recipes, and project launcher.

The launcher expects PowerShell 7 and the CLI aliases from the local PowerShell
profile. Those account wrappers and credentials are not stored in this repository.

## Install on another Windows machine

Merge or move any existing `.wezterm.lua` before creating the hardlink. Both paths
must be on the same volume.

```powershell
$repoPath = Join-Path $env:USERPROFILE 'configs'
$configPath = Join-Path $env:USERPROFILE '.wezterm.lua'
git clone https://github.com/lveillard/configs.git $repoPath
if (Test-Path -LiteralPath $configPath) {
  throw 'An existing WezTerm configuration must be preserved or merged first.'
}
New-Item -ItemType HardLink -Path $configPath -Target (Join-Path $repoPath 'wezterm/wezterm.lua')
```

Then install the Pi settings (see [`pi/README.md`](pi/README.md) for what is tracked):

```powershell
pwsh -File pi/sync.ps1          # report drift against the active profile
pwsh -File pi/sync.ps1 -Push    # install into $env:PI_CODING_AGENT_DIR or ~/.pi/agent-plus
```

## Pi agent settings

`pi/models.json` and `pi/settings.json` are the only tracked files. `auth.json`
(API keys), `sessions/`, `bin/`, `npm/`, `models-store.json` and `mcp-cache.json` stay
out: credentials and Pi-managed state.

## Shortcuts

| Action | Shortcut |
| --- | --- |
| Rename tab; empty name restores automatic titles | Ctrl+Shift+W |
| Appearance menu | Right-click |
| Project launcher | Ctrl+Shift+N or Ctrl+Shift+O |
| New tab | Ctrl+Shift+T |
| Horizontal / vertical split | Ctrl+Shift+D / Ctrl+Shift+E |
| Switch panes | Alt+Arrow |
| Switch tabs 1–5 | Alt+1–5 |

## Validation

Run from the repository root with WezTerm on `PATH`:

```powershell
pwsh -NoProfile -File ./wezterm/test.ps1
git diff --check
```

The checks load the real configuration through WezTerm and exercise repeated GPU
discovery, inactive-tab and inactive-split title isolation, and conversation title
formatting. The runner requires an explicit success marker because `show-keys`
can otherwise return success after falling back from a Lua configuration error.

## Codex startup color responses

Codex 0.154.0 on Windows waits 100 ms for OSC 10/11 color responses. Its
[startup probe](https://github.com/openai/codex/blob/rust-v0.154.0/codex-rs/tui/src/terminal_probe/windows.rs)
only removes complete replies received during that window; later replies can
reach the keyboard reader and appear as `]10;rgb:...` / `]11;rgb:...` in the composer.

WezTerm re-evaluates this configuration when account colors change. Caching GPU
discovery removes repeated enumeration from that path. Measurements on the local
Windows setup improved from initial replies of 407–454 ms to 14–84 ms across six
final color-query trials. Controlled late delivery reproduced the exact Codex
composer leak; normal startup trials were clean both before and after the change.

This reduces a local latency contributor. The upstream fix requires the input
reader to retain response-parsing state across the startup timeout, including
fragmented replies, while preserving keyboard input and pasted text. Raising the
timeout alone does not resolve that protocol-handling problem.

## Remote dev servers (`dev-servers/`)

One Azure VM per project, described using [`dev-servers/boxes.example.json`](dev-servers/boxes.example.json).
Copy it to `dev-servers/boxes.json` and fill in your own settings locally; that file is ignored by Git.
See [`dev-servers/README.md`](dev-servers/README.md).

The [session blueprint](dev-servers/SESSIONS.md) explains the Windows client, SSH,
the VM's WezTerm mux, workspace picker, and the tmux-backed agent lifecycle.
The actual session manager is [`sessions.lua`](dev-servers/launcher/sessions.lua).

Before running provisioning or installers, configure your local inventory, binary
paths, account aliases and project paths. The standalone tooling under
`dev-servers/dev-server-1/` uses `devuser` and `dev-server-1` as example values.
Use matching WezTerm versions on the client and server.

Credentials, login state, SSH private keys, Terraform state and conversations stay
outside Git. To scan both the complete fetched history and the working tree:

```sh
gitleaks git . --log-opts="--all --full-history" --redact
gitleaks dir . --redact
python tools/check-public-data.py
```

The sole scanner exception is the literal environment-variable name
`QWEN38_API_KEY` in a list of variables to clear, not a credential value.

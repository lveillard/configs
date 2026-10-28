# How the VM sessions work

Tooling snapshot from 2026-10-28, published with example hostnames and paths.
The shared session manager used by the Windows shortcuts lives in
[`launcher/sessions.lua`](launcher/sessions.lua). The old `wezterm/remote/` copies
in earlier commits predate the multi-VM launcher.

## The connection and ownership

1. On Windows, [`launch.ps1`](launcher/launch.ps1) selects a VM from
   a local `boxes.json` copied from [`boxes.example.json`](boxes.example.json), checks SSH over Tailscale and opens its WezTerm GUI.
   The local Azure login can start a stopped VM. Reopening normally reuses the GUI.
2. [`wezterm.lua`](launcher/wezterm.lua) attaches that GUI to the VM's WezTerm mux
   through SSH. The server is `wezterm-mux.service`, listening on the private Unix
   socket `~/.local/state/wezterm/dev-server.sock`. There is no public WezTerm port.
   The service and server config are defined in [`infra/cloud-init.yaml`](infra/cloud-init.yaml).
3. The mux owns the remote windows, tabs and panes. A **workspace** groups them into
   a named session. A **Git worktree** is a separate code checkout; creating a
   workspace does not create a worktree.
4. On the original VM, [`agent-spawn`](dev-server-1/dev-server/agent-spawn) also puts
   the agent in a detached **tmux session**, then attaches a WezTerm pane to it.
   That extra process owner keeps the agent alive even when its WezTerm pane ends.

WezTerm's [multiplexing documentation](https://wezterm.org/multiplexing.html) and
tmux's [getting-started guide](https://github.com/tmux/tmux/wiki/Getting-Started)
describe the underlying client/server and detach/attach behaviour.

## The session picker

| Action | Shortcut / behaviour |
| --- | --- |
| Find an existing workspace | `Ctrl+Shift+S`; type to filter, Enter to attach |
| Create a named workspace | `Ctrl+Shift+A` or `+ Nueva sesion` in the picker |
| Create the same name again | Reuses the existing workspace; repeated pending requests are suppressed |
| Close a workspace's panes | Delete in the picker, then explicit confirmation |
| Return after disconnecting | Reopen the box shortcut; the last workspace is remembered locally |

The picker labels panes using `CLI_IDENTITY`, `CLI_MODEL`, and explicit terminal
status/title information. Quiet output alone is not proof that an agent is idle.
It lists WezTerm workspaces, not every detached tmux session. Deleting panes from
this picker can leave a tmux-backed agent running: use `agent-kill` to stop it.

Session creation uses the attached client's mux domain and the real active pane
after the prompt overlay closes. This avoids the Windows-to-Linux command encoding
and stale overlay-pane errors fixed in the older implementation. The picker guard
also expires so a dismissed overlay cannot permanently block `Ctrl+Shift+S`.

## Install and operate an agent

The shared launcher is used on all four VMs. The agent wrappers below were checked
on `dev-server-1`; they are separate from the tmux `t` helper on the other boxes.
On the target VM, with this checkout available and WezTerm, tmux, Bash and Python 3
installed, copy the wrappers into the user's path:

```sh
mkdir -p ~/.local/bin
install -m 755 dev-servers/dev-server-1/dev-server/agent-spawn ~/.local/bin/
install -m 755 dev-servers/dev-server-1/dev-server/agent-kill ~/.local/bin/
```

Run these commands **on the VM**, using an existing checkout and installed harness:

```sh
export WEZTERM_UNIX_SOCKET="$HOME/.local/state/wezterm/dev-server.sock"
agent-spawn review-123 "$HOME/projects/my-project" codex my-model -- codex
# The launcher prints the new remote pane ID. Use that ID, not a GUI-local pane ID.
wezterm cli --no-auto-start list --format json
wezterm cli --no-auto-start send-text --pane-id 41 "Review the current change"
printf '\r' | wezterm cli --no-auto-start send-text --no-paste --pane-id 41
wezterm cli --no-auto-start get-text --pane-id 41 | tail -n 40
```

Use a unique session name made from letters, digits, `_` and `-`. Other characters
are replaced with `_` for the tmux name, so different workspace names can otherwise
collide. A duplicate tmux session is rejected. `AGENT_SPAWN_TMUX=0` opts out of tmux;
the wrapper also falls back to a plain pane if tmux is not installed.

If the WezTerm pane has gone but the agent is still alive:

```sh
tmux list-sessions
tmux attach-session -t '=review-123'
# Ctrl+b, then d detaches again.
# This deliberately stops the named tmux session and closes its remaining panes:
agent-kill review-123
```

`agent-kill` in this snapshot additionally validates its argument, passes the name
as data to Python, and checks the mux identity before closing panes. These fixes
are in the repo; the installed VM copy captured during the review predates them.

## What survives

| Event | Plain WezTerm pane | Agent started with tmux enabled |
| --- | --- | --- |
| Network drops / laptop disconnects | Remains on the running VM | Remains on the running VM |
| Explicitly kill the WezTerm pane | Its attached process can terminate | tmux client closes; agent remains |
| Stop or restart the VM | Live process ends | Live process ends |
| Stop the named tmux session | Not applicable | Agent ends |

This is process persistence while the VM stays alive. After a reboot, use the
harness's saved conversation ID to resume and a written report to recover the task.
Pane ID, workspace name, tmux session name and harness conversation ID are distinct.

The separate [Dev Sessions](dev-server-1/dev-terminal/README.md) interface manages
tmux directly. Its list and the WezTerm workspace picker are different views.

## Validation

`pwsh -NoProfile -File wezterm/test.ps1` checks the local WezTerm configuration.
`python3 dev-servers/tests/test-agent-tools.py` runs isolated wrapper regressions
on Linux using fake tmux/WezTerm executables, without touching live sessions.
The existing `check-create-once.py` and `check-picker.py` are interactive VM/GUI
checks; they open test windows and are intended for an explicit integration run.

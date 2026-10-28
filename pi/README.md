# Pi agent settings

Hand-editable [Pi](https://github.com/earendil-works/pi-mono) configuration for this
machine, kept under version control and installed into `~/.pi/agent*` by `sync.ps1`.

| File | Holds | Pi rewrites it? |
| --- | --- | --- |
| `models.json` | providers and custom models — the `xiaomi` V2.6 family and the official `DeepSeek V4.1 Flash` name/limits | no |
| `settings.json` | theme, default provider/model, thinking level, enabled models, packages, compaction | yes, `lastChangelogVersion` on every upgrade (and the file generally) |

## What is deliberately not here

`auth.json` (API keys), `sessions/`, `bin/`, `npm/`, `models-store.json` and
`mcp-cache.json`. The first is a credential; the rest is Pi-managed state. `sync.ps1`
only copies the two allowlisted files above. Both installers reject common credential
patterns in source files; this is a heuristic, not a guarantee. Review diffs before
committing. Pull validates both profile source files before changing the repo.

## Usage

```powershell
pwsh -File pi/sync.ps1                      # drift check; exit 1 if the profile differs
pwsh -File pi/sync.ps1 -Push                # repo -> active profile
pwsh -File pi/sync.ps1 -Pull                # active profile -> repo (capture local changes)
pwsh -File pi/sync.ps1 -AllProfiles         # drift across agent and agent-plus only
pwsh -File pi/sync.ps1 -Target <dir> -Push  # a specific profile
```

`Push` preserves the `lastChangelogVersion` already present in the profile, and both
`Status` and `Push` ignore that key when comparing, so a Pi upgrade does not show up
as drift.

`-Pull -AllProfiles` and `-Target -AllProfiles` are rejected as ambiguous. The separate
`agent-plus-jev` profile is only touched when selected explicitly with `-Target`.

## Why a script instead of a hardlink

`~/.wezterm.lua` is a hardlink to `wezterm/wezterm.lua` because WezTerm only reads it.
Pi **saves** `settings.json` (upgrades, theme changes), and a save-by-rename silently
breaks a hardlink — the repo copy would quietly stop being the live config. A one-way
copy keeps the repo authoritative and makes drift explicit.

## Machine-specific values

`settings.json` assumes `sessionDir: ~/.pi/agent/sessions` and a relative package path,
`../../Desktop/Projects/pi-session-ledger`, resolved from the profile directory. Adjust
both when installing on another machine.

For a remote/Linux profile, copy this `pi/` directory and use its Python 3 installer
(no additional dependencies). It reads the same adjacent JSON sources, sets
`sessionDir` to `<target>/sessions`, and optionally omits filesystem package sources
such as the Windows ledger checkout:

```sh
python3 pi/sync.py --target ~/.pi/agent-plus --push --omit-local-packages
python3 pi/sync.py --target ~/.pi/agent-plus --check --omit-local-packages
```

Use the same options for push and check. Check is the default and exits 1 on drift;
invalid input exits 2. Without `--omit-local-packages`, package sources are preserved.
With it, only npm, git, HTTP(S), and SSH `git@` package sources are retained (including
package objects with a `source` field). Both installers preserve the target's
`lastChangelogVersion`; neither copies credentials or other profile state. The Python
installer creates a missing target directory and supports push/check only.

## Profiles on this machine

| Profile | State |
| --- | --- |
| `~/.pi/agent-plus` | active (`PI_CODING_AGENT_DIR`) |
| `~/.pi/agent` | stale — last synced at Pi 0.85.1; kept in sync by this repo, verify before deleting |
| `~/.pi/agent-plus-jev` | separate profile, not tracked here |

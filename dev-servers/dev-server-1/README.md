# Standalone session tooling

This directory contains the agent wrappers and the optional **Dev Sessions** tmux
interface. `dev-server-1` and `devuser` are example host and login names; replace
them when adapting these standalone files.

- [`dev-server/agent-spawn`](dev-server/agent-spawn) starts an agent in a named
  workspace, with tmux persistence enabled by default when tmux is available.
- [`dev-server/agent-kill`](dev-server/agent-kill) stops that named tmux session and
  closes the associated WezTerm panes.
- [`dev-terminal/`](dev-terminal/README.md) provides a separate tmux session picker,
  shell setup and isolated CLI profiles. Its migration scripts read local account
  state; configure the destination and review their inputs before running them.
- `cloud-init.yaml` is the standalone mux-service example. The shared Terraform
  template in [`../infra/`](../infra/) is the multi-VM provisioning path.

Start with [How the VM sessions work](../SESSIONS.md), then configure the shared
[example inventory](../boxes.example.json) in an ignored local `boxes.json`.
Public IPs, cloud identifiers, private hostnames and incident/operations notes do
not belong in this public repository.

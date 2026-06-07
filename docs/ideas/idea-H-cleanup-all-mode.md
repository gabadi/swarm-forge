# Idea H — swarm-cleanup --all Mode

**Status:** Proposed

## Context

`swarm-cleanup.sh` currently takes positional arguments: `<window-ids-file> <session...>`. It tears down a specific swarm instance identified by those arguments. The first window in `swarmforge.conf` triggers this cleanup on close.

There is no way to tear down all running swarms in one shot. If the operator has multiple projects running simultaneously, or if a swarm crashed and left orphaned tmux sessions, cleanup requires knowing each session name and running the script per instance.

## Decision

Add an `--all` branch to `swarm-cleanup.sh`:

```sh
if [ "$1" = "--all" ]; then
  # Kill every swarmforge-* tmux session
  tmux ls 2>/dev/null | grep '^swarmforge-' | cut -d: -f1 | xargs -I{} tmux kill-session -t {}
fi
```

The existing positional `<window-ids-file> <session...>` form is preserved unchanged in the `else` branch — the normal cleanup path is untouched.

**Files changed:** `swarmforge/scripts/swarm-cleanup.sh` on `main` — additive `--all` branch only.

**cmux:** The `--all` mode targets tmux sessions. If Idea A's harness tracks active swarms in `.swarmforge/`, an `--all` equivalent for cmux (delete all SwarmForge workspace groups) could be added using `cmux workspace-group list --json | jq` — same pattern as the existing cmux teardown in `swarm-mux.sh`.

## Tradeoffs

**What improves:**
- One command tears down everything — useful for recovery after crash, or end of day cleanup
- The existing cleanup path is untouched — no regression risk

**What doesn't change:**
- Window-id file tracking is not affected — `--all` discovers sessions via `tmux ls` directly

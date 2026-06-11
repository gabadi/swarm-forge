# AGENTS.md

## Gotchas

- **Never push, create issues, or open PRs against `unclebob/swarm-forge` (the upstream remote) — ever.** `gh` defaults to the upstream in this repo; always pass `--repo gabadi/swarm-forge` explicitly or run `gh repo set-default gabadi/swarm-forge` at session start. All issue tracking, commits, and PRs go to `gabadi/swarm-forge` (origin) only.

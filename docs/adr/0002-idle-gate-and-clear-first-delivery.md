---
status: accepted
---

# Idle gate and clear-first delivery via a per-role Stop hook

The fork uses upstream's handoff harness as-is (queue, scripts, append-only `logbook.jsonl`); the only engine discrepancy is here. Upstream agents do setup work at startup and never clear context between tasks (delivery is an immediate `tmux send-keys`; "don't interrupt" relies on the terminal app buffering typed input). The fork instead requires each role to (1) do nothing until it receives a handoff and (2) begin every task with a cleared context:

- **Idle gate** — a prompt rule ("Wait for a handoff. Do not act without one.") plus removal of the startup-install directives from role prompts (install work moves to the setup skill). Pure additive prompt edits.
- **Clear-first delivery** — a per-role **Stop hook** that, on idle, drains a durable inbox: if a *work* handoff is waiting it runs `/clear` → re-inject the role bundle (`codex`/`grok` only; for `claude` the bundle lives in the system prompt and survives `/clear`) → deliver the message. This needs one **non-additive** transport change: a handoff must be dropped into a durable inbox the hook reads, not typed straight into the terminal, so `/clear` cannot race buffered input. That single redirect is the recurring sync-friction point.

"Ready" is therefore implicit (idle + empty queue = ready). Upstream's startup "I'm awake" ping is kept only as an operator-visible **presence** signal — stamped a distinct `presence` type and excluded from the clear-first path, so the Stop hook never clears for it.

## Considered options

- **Keep a full fork-owned harness for delivery** — rejected: a parallel harness conflicts with upstream's actively-developed one on every sync, so we ride upstream's and diverge only as above.
- **Rely on upstream's app-buffering model, skip `/clear`** — rejected: loses the required per-task context reset.
- **Orchestrator-in-code** (`docs/proposals/2026-06-11-factory-line-refactor.md`) — deferred as a future bet; it maximizes divergence and is a re-architecture, not a sync move.

## Open

- Inbox location: reuse upstream's `.swarmforge/handoffs/queue/` vs a fork-owned dir.
- Suppress upstream's immediate send-keys nudge globally vs per-cleared-role.
- `/clear` cost is backend-dependent; the current `six-pack` `swarmforge.conf` runs all six roles on `codex`, so bundle re-injection is required today.

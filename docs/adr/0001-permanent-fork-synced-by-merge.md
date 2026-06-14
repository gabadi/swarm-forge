---
status: accepted
---

# Permanent fork of unclebob/swarm-forge, synced by merge

This repo is a permanent fork of `unclebob/swarm-forge` (remote `upstream`); nothing is contributed back. Upstream moves fast, so we keep current by **merging** `upstream/<branch>` into our branches — never rebasing — because the fork is published/shared and rebasing would rewrite shared history and re-surface every conflict on each sync. `git rerere` is enabled (`rerere.enabled`, `rerere.autoupdate`) so conflict resolutions replay automatically. Every divergence should be **additive** (a new file or an appended rule) and recorded as its own ADR in this directory; a non-additive edit to an upstream line is a conscious, documented cost. Two branches are maintained: `main` (shared scripts + these docs) and `six-pack` (runnable: role prompts, `swarmforge.conf`, templates).

## Considered options

- **Rebase onto upstream** — rejected: the fork is shared/published; rebasing rewrites history others may track and re-resolves every conflict each cycle.
- **Snapshot upstream and stop tracking** — rejected: the goal is to stay current with a fast-moving upstream, not freeze it.

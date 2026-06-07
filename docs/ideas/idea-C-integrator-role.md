# Idea C — Integrator Role

**Status:** Proposed  
**Depends on:** Idea A (harness serializes delivery, making architect batch-all-queued rule irrelevant)

## Context

The current pipeline ends at the architect (four-pack) or QA (six-pack). No role owns landing — getting work from the role branch onto `main`. Consequences:

- Completed features strand on role branches indefinitely
- The user must manually create PRs, watch CI, and merge
- When CI fails, no role is responsible for routing the failure back to the appropriate owner
- The architect batches multiple refactorer handoffs together, which would bundle multiple features into one PR if landing were added — making failure attribution impossible

## Decision

Add an integrator role as the terminal stage of the pipeline, and move the specifier to its own worktree.

### Pipelines

**Four-pack:**
```
specifier → coder → refactorer → architect → integrator → (notify specifier)
```

**Six-pack:**
```
specifier → coder → cleaner → architect → hardener → UX Reviewer → QA → integrator → (notify specifier)
```

The integrator is always the terminal role. It owns landing only — no code changes.

### Integrator lifecycle

1. Receives handoff from the terminal quality role (architect in four-pack; QA in six-pack) with branch + commit hash
2. Creates one PR per feature: `gh pr create` from the handoff branch
3. Watches CI: `gh pr checks --watch`
4. On green: merges (`gh pr merge --delete-branch`)
5. Notifies specifier of completion
6. On CI red: routes failure back to the owning role (see back-routing in Idea E)
7. `agent-retro` before idle

### CI-red routing

- Small change (≤ ~10 lines) or autofixable (lint/format): fix in-place, update the same PR
- Failing test → coder
- Failing coverage/CRAP/DRY → cleanliness role (refactorer in four-pack; cleaner in six-pack)
- Failing arch-check → architect
- Depth cap N=3: if three routing cycles fail to clear CI, leave PR open with FAILED comment, go idle

### Specifier worktree change

The specifier moves from `master` to its own `specifier` worktree. Step 1 of the specifier lifecycle becomes: reset to `origin/main` before each new job. This is required because the integrator merges PRs to `main` — the specifier must start each job from a clean trunk state, not from accumulated uncommitted work.

**swarmforge.conf change (both branches):**
```
window specifier <agent> specifier   # was: master
```

**Files changed:**
- `four-pack` + `six-pack`: `swarmforge/swarmforge.conf` — add integrator window; change specifier from `master` to `specifier` worktree
- `four-pack` + `six-pack`: `swarmforge/roles/integrator.prompt` (new)
- `four-pack` + `six-pack`: `swarmforge/roles/specifier.prompt` — add step 1: reset to `origin/main`

### Consequence for architect

Upstream's architect prompt says "merge all queued refactoring handoffs together." With the integrator, this would bundle multiple features into one PR and corrupt CI failure attribution. With Idea A's harness serializing delivery (one message at a time), the batching scenario cannot happen — the architect always receives one handoff. No prompt change needed; the harness makes the upstream batching rule inert.

## Tradeoffs

**What improves:**
- Features land without human intervention
- CI failures route to the owning role automatically
- No feature can strand on a branch indefinitely
- Specifier always starts from a clean trunk state

**What gets more complex:**
- New role prompt to maintain (permanent divergence from upstream)
- CI routing logic adds complexity and a new failure mode (depth-cap exhaustion)
- Specifier worktree change requires updating `swarmforge.conf` on both runnable branches

## Alternatives considered

**User handles landing manually:** No new role, no maintenance cost. Works fine if the user is available and features don't queue up. Rejected as the primary mode — defeats the purpose of an autonomous swarm for delivery.

**Extend the architect to handle landing:** Architect already owns the last quality gate; adding landing would overload the role (structure + delivery + CI triage). Clean role boundaries matter for attribution. Rejected.

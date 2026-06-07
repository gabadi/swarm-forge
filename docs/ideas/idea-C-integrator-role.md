# Idea C — Integrator Role

**Status:** Proposed  
**Depends on:** Idea A (harness serializes delivery, making architect batch-all-queued rule irrelevant)  
**Open question:** Do the target projects where swarmforge is installed have a CI pipeline?

## Context

The current pipeline ends at the architect (four-pack) or QA (six-pack). No role owns landing — getting work from the role branch onto `main`. Consequences:

- Completed features strand on role branches indefinitely
- The user must manually create PRs, watch CI, and merge
- When CI fails, no role is responsible for routing the failure back to the appropriate owner
- The architect batches multiple refactorer handoffs together, which would bundle multiple features into one PR if landing were added — making failure attribution impossible

## Decision

Add an integrator role as the final stage of the pipeline:

```
specifier → coder → refactorer → architect → integrator → (notify specifier)
```

The integrator's mandate is mechanical: it owns landing only, no code changes.

### Integrator lifecycle

1. Receives architect handoff (branch + commit hash)
2. Creates one PR per feature: `gh pr create` from the architect's branch
3. Watches CI: `gh pr checks --watch`
4. On green: merges (`gh pr merge`)
5. Runs post-merge gate (project-specific verification command if configured)
6. Notifies specifier of completion
7. On CI red: routes failure back to the owning role (see back-routing in Idea E)

### CI-red routing

- Small change (≤ ~10 lines) or autofixable (lint/format): fix in-place, update the same PR
- Failing test → coder
- Failing coverage/CRAP/DRY → refactorer
- Failing arch-check → architect
- Depth cap N=3: if three routing cycles fail to clear CI, leave PR open with FAILED comment, go idle

### Consequence for architect

Upstream's architect prompt says "merge all queued refactoring handoffs together." With the integrator, this would bundle multiple features into one PR and corrupt CI failure attribution. With Idea A's harness serializing delivery (one message at a time), the batching scenario cannot happen — the architect always receives one handoff. No prompt change needed; the harness makes the upstream batching rule inert.

### Consequence for specifier worktree

The specifier may need its own worktree (not `master`) so it can reset to `origin/main` after each landing without affecting other roles. Decision deferred — depends on whether the specifier currently accumulates stale state between jobs.

## Tradeoffs

**What improves:**
- Features land without human intervention
- CI failures route to the owning role automatically
- No feature can strand on a branch indefinitely

**What gets more complex:**
- New role prompt to maintain (permanent divergence from upstream)
- CI routing logic adds complexity and a new failure mode (depth-cap exhaustion)
- If CI does not exist on the target project, the integrator has nothing to do and adds latency

**CI dependency is the gate:** This idea is only worth the maintenance cost if target projects have CI that provides meaningful signal. Without CI, the integrator reduces to "create PR, merge" — a two-step automation that may not justify a full new role.

## Open questions

**Does the target project have CI?** The integrator's value is almost entirely in CI-red routing. If the answer is no, a simpler approach (user creates PRs manually) may be better. This question must be answered before designing the integrator prompt.

**Post-merge gate:** What is the project-specific verification command after merge? Configurable in `swarmforge.conf`? Or specified in `project.prompt`?

## Alternatives considered

**User handles landing manually:** No new role, no maintenance cost. Works fine if the user is available and features don't queue up. Rejected as the primary mode — defeats the purpose of an autonomous swarm for delivery.

**Extend the architect to handle landing:** Architect already owns the last quality gate; adding landing would overload the role (structure + delivery + CI triage). Clean role boundaries matter for attribution. Rejected.

# Idea E — Back-Routing Defects

**Status:** Proposed

## Context

The forward pipeline is: specifier → coder → refactorer → architect (→ integrator if Idea C is adopted).

Each role is scoped to its quality gate. When a role discovers a defect it doesn't own — a structural problem found by the refactorer that is actually a coder bug, or a spec discrepancy found by QA — the current pipeline has no defined path. Both available moves are wrong:

- **Fix out-of-role:** Refactorer fixes a coder bug. Now the fix bypasses the mutation gate the coder would have applied, ships under-mutated, and attribution is corrupted.
- **Push broken forward:** Refactorer hands off a known defect to the architect. The defect propagates, attribution is lost, and a downstream role eventually fails in a confusing context.

The concrete QA scenario: QA finds a discrepancy between the implementation and the spec. Without back-routing, QA blocks silently or fails with no clear next action.

## Decision

Add a single rule to `constitution/workflow.prompt`:

> When you discover a defect you do not own, route it back to the directly-upstream role. Include: the failing step, the raw error output, your diagnosis, and a repro recipe. Autofixable issues (formatting, linting) are excepted — fix those in place.

**"Directly-upstream" means one step back in the pipeline.** If QA finds a spec discrepancy, it routes to hardener. Hardener routes to architect if it doesn't own it. And so on until it reaches the owning role. Multi-hop chains are acceptable — in practice, most defects are local to the adjacent role, so chains are short.

**Files changed:** `swarmforge/constitution/workflow.prompt` on both runnable branches — one additive rule, no upstream content removed.

## Tradeoffs

**What improves:**
- Clear path for every defect — no role is stuck
- Defects route to their owner without bypassing quality gates
- Attribution stays clean — the owning role applies its own rules to its own fix

**What gets less precise:**
- Multi-hop routing for deep defects (e.g. QA → hardener → architect → refactorer → coder for a spec bug) is mechanical relay work with no value at each intermediate hop. Accepted — this case is rare in practice; adding explicit ownership maps to each role would add more prompt complexity than occasional extra hops cost.

**Autofixable exception:** Formatting and lint failures are mechanical and safe for any role to fix in place. Routing these back would waste a full pipeline cycle for a one-line change.

## Alternatives considered

**Route to the owning role directly (skip hops):** Requires each role to know the full ownership map of every defect type. Adds prompt complexity per role. The "directly-upstream" rule is one line in the constitution; ownership-map routing would be a table in every role prompt. Rejected.

**Let the integrator handle all back-routing (Idea C):** The integrator owns CI-red routing from the landing stage. But intermediate roles need a path for defects discovered before landing — waiting until the integrator is fragile and propagates defects through multiple stages. The integrator's routing is complementary, not a replacement. Both rules are needed if Idea C is adopted.

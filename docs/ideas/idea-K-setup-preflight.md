# Idea K — Setup / Preflight

**Status:** Proposed  
**Required by:** Idea J (entire must be enabled before sessions can be tracked)  
**Open question:** Implemented as an interactive skill or as an automatic preflight check at swarm launch?

## Context

Upstream's role prompts include startup install directives ("At startup, install the language mutation tool…"). Idea D removes these from the role prompts — they don't belong in per-job startup.

But the tools still need to be installed somewhere. Additionally, Idea G (per-tech engineering file) requires a language selection step at project setup time. Idea J requires `entire enable` + `entire agent add <backend>` per project.

Currently, none of this has a defined home. The operator is expected to handle it manually before running `./swarm`.

## Decision

Create a one-time project setup step that covers:
1. **Tool installation check** — verify required tools (mutation, CRAP, DRY, language-specific) are installed; fail with a clear message if not
2. **`entire enable`** — enable session tracking in the project repo
3. **`entire agent add <configured-backend>`** — register the swarm's agent backend with entire
4. **Engineering template selection** — if Idea G is adopted, prompt for project language and write `engineering.prompt`
5. **Write `.swarmforge/setup-complete` sentinel** — marks setup as done so swarm launch can verify

### Option A — Interactive skill

A `/setup-swarmforge` slash command (or extension of `/enabling-swarm-forge`) that runs the steps above interactively. The operator runs it once when initializing a project. Explicit, operator-controlled, visible.

**Pro:** Operator sees exactly what is being installed/configured. Easy to re-run if setup changes.  
**Con:** Requires the operator to know to run it. A forgot-to-run-setup failure shows up at runtime as confusing errors.

### Option B — Automatic preflight at swarm launch

`./swarm` runs a preflight check before launching the swarm. If `.swarmforge/setup-complete` does not exist (or is stale), run setup automatically before continuing. The operator runs `./swarm` as always; setup happens transparently on first run.

**Pro:** Zero extra step for the operator. Setup always runs before the swarm starts.  
**Con:** `./swarm` becomes interactive on first run (language selection, etc.) — may surprise operators who expect it to launch immediately. Any setup failure blocks the swarm entirely.

## Open questions

**Which option?** The key question is: how much friction is acceptable at first launch, and how bad is it to forget setup? If the swarm silently misbehaves without setup (wrong tools, no retros), Option B (automatic) is safer. If the operator reliably knows to run setup, Option A (explicit) is cleaner. Recommend Option B — the swarm is already interactive on first run (opens terminal windows, downloads scripts), so a setup prompt fits naturally.

**Re-run semantics:** If the operator changes the project language or backend, how does setup re-run? Options: delete `.swarmforge/setup-complete` manually, or add a `./swarm setup` subcommand.

## Alternatives considered

**Keep upstream's per-launch install directives in role prompts:** Every role launch checks and installs tools. Slow, redundant on mature projects. Rejected — Idea D removes these for good reason.

**Document setup in README, trust the operator:** No code change. Works until it doesn't. A forgotten setup step silently breaks retros (no `entire` data) or uses the wrong tool commands (wrong engineering.prompt). Rejected as too fragile for an unattended swarm.

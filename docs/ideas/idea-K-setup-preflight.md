# Idea K — Setup / Preflight

**Status:** Proposed  
**Required by:** Idea J (entire must be enabled before sessions can be tracked)

## Context

Upstream's role prompts include startup install directives ("At startup, install the language mutation tool…"). Idea D removes these from the role prompts — they don't belong in per-job startup.

Tool installation is handled by Idea G's per-language setup prompt. What remains without a defined home is `entire` session tracking setup — needed for raw traces that `agent-retro` analyzes.

Currently the operator is expected to run this manually before `./swarm`.

## Decision

`./swarm` runs an automatic preflight on first launch. If `.swarmforge/setup-complete` does not exist, it runs setup before continuing.

### Setup steps

1. `entire enable --agent claude-code --telemetry=false` — enable session tracking in the project repo
2. `entire agent add <backend>` for each unique backend in `swarmforge.conf` — register all configured agent backends
3. Write `.swarmforge/setup-complete` sentinel — marks setup as done

The backends are derived automatically from `swarmforge.conf` — no user input required. The swarm script already reads this file to launch roles.

### Re-run semantics

If the operator adds a new backend or changes the configuration: delete `.swarmforge/setup-complete` manually, or run `./swarm setup` as a subcommand. Either triggers setup again.

**Files changed:**
- `four-pack` + `six-pack`: `./swarm` — preflight block added before role launch

## Tradeoffs

**What improves:**
- Zero extra step for the operator — setup runs transparently on first launch
- Backend registration is always consistent with `swarmforge.conf`
- No silent failure from forgotten setup

**What gets more complex:**
- `./swarm` gains a preflight block; first launch is slightly slower
- Any `entire` failure blocks the swarm — must handle gracefully (warn and continue if `entire` is not installed)

## Alternatives considered

**Interactive skill (`/setup-swarmforge`):** Requires the operator to know to run it. A forgotten setup step silently breaks traces and retros. Rejected — automatic is safer.

**Keep upstream's per-launch install directives in role prompts:** Every role launch checks and installs tools. Slow, redundant on mature projects. Rejected — Idea D removes these for good reason.

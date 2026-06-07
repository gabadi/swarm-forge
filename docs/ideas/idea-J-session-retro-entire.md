# Idea J — Session Retro via `entire` + `agent-retro`

**Status:** Proposed  
**Depends on:** Idea K (entire must be enabled and agent hooks installed before sessions can be tracked)

## Context

Role agents run in separate processes with separate session transcripts. Without structured close-out, session stories are lost — what the role did, where it struggled, what it tried that didn't work.

`entire` and `agent-retro` are complementary, not alternatives:

- **`entire`** — raw trace layer. Once set up via `entire agent add <backend>`, it automatically collects session checkpoints across all configured agent backends (claude-code, codex, opencode, etc.) in a unified format. No explicit call needed during sessions — collection is automatic.
- **`agent-retro`** — per-session analysis. Runs within the agent's own turn as the close-out step. Produces friction analysis and improvement proposals from the session.

The original Idea J framing (replacing `agent-retro` with `entire dispatch --local`) was wrong. `entire dispatch --local` generates an on-demand summary from `entire`'s checkpoints — it is for the operator, not for unattended roles. `agent-retro` remains the per-session retro for role agents.

## Decision

Two things happen per session:

1. **`entire` collects automatically** — no role prompt change needed. Traces are captured by the hooks `entire agent add` installs (Idea K). Backend-agnostic.

2. **`agent-retro` runs within the role turn** — as the explicit close-out step in every role's lifecycle, before going idle. This is the standard "agent-retro before idle" pattern already used in melech-mini-apps roles.

**Files changed:**
- `four-pack` + `six-pack`: `swarmforge/roles/*.prompt` — `agent-retro before idle` added as final lifecycle step to each role (if not already present)
- No Stop hook change needed — `entire` collection is automatic, `agent-retro` is within the turn

**Condition:** If `entire` is not set up, traces are silently absent — retro still runs via `agent-retro` but without the raw trace backing. No failure.

## Tradeoffs

**What improves:**
- Raw traces are backend-agnostic and automatic — captured for every agent type configured in `swarmforge.conf`
- Per-session retro runs reliably within the turn — not dependent on Stop hook timing
- Operator can run `entire dispatch --local` on demand to review cross-session summaries

**What requires setup:**
- `entire enable` + `entire agent add <backend>` must run at project setup (Idea K)

## Alternatives considered

**`entire dispatch --local` in Stop hook as retro replacement:** `entire dispatch` is a summary tool for operators, not a per-session friction analysis for agents. It does not produce actionable proposals within the agent turn. Rejected — `agent-retro` is the right tool for per-session close-out.

**No retro at all:** Session stories are lost. Rejected.

# Idea J — Session Retro via `entire`

**Status:** Proposed  
**Depends on:** Idea K (entire must be enabled and agent hooks installed before any session can be tracked)

## Context

Role agents run in separate processes with separate session transcripts. When a session ends (agent stops, compaction, or explicit close), the session story is lost — what the role did, where it struggled, what it tried that didn't work.

`agent-retro` (used in melech) reads Claude Code's JSONL session transcripts directly and produces structured friction analysis + improvement proposals. It works for Claude Code only — it cannot read codex, copilot, or other backend session formats. Since swarmforge supports multiple backends (`codex`, `claude`, `copilot`, `grok`), a Claude-Code-specific retro tool creates an uneven experience.

`entire` is an agent-agnostic session tracking tool. It hooks into multiple agent CLIs (`claude-code`, `codex`, `copilot-cli`, `cursor`, etc.) via `entire agent add <backend>` and tracks checkpoints in a unified format. `entire dispatch --local` generates a session summary from those checkpoints without depending on agent-specific transcript formats.

## Decision

At session end (Claude Code Stop hook — same mechanism as Idea A), each role runs:

```sh
entire dispatch --local
```

This generates a dispatch summarizing what the role did during the session. Dispatches are stored by `entire` in its local state.

For cross-session root-cause analysis, `retro-triage` (an existing skill in the operator's environment) runs periodically across all role session dispatches to identify systemic failure patterns and propose improvements.

**This replaces `agent-retro` for swarmforge roles.** The `agent-retro` skill's value (friction analysis + proposals) is preserved through `retro-triage`'s batch analysis, but without the per-agent JSONL dependency.

**Files changed:** `swarmforge/scripts/swarmforge.sh` — the Stop hook written to each role's `.claude/settings.local.json` gains an `entire dispatch --local` call (conditioned on `entire` being available).

**Condition:** If `entire` is not set up (not enabled or agent not registered), the Stop hook silently skips the dispatch. No failure.

## Tradeoffs

**What improves:**
- Agent-agnostic — works for codex, claude, copilot, or any `entire`-supported backend
- No custom per-agent session parsing to maintain
- `retro-triage` cross-session analysis available for all roles

**What requires setup:**
- `entire enable` + `entire agent add <backend>` must run at project setup (Idea K)
- Without setup, retros are silently skipped — no error, no retro

**What `entire dispatch` does not provide vs `agent-retro`:**
- Interactive walkthrough — `agent-retro` walks through proposals one by one for approval. `entire dispatch` produces a summary; actionability comes from `retro-triage` in a separate operator session, not from the role agent itself.
- Per-session friction analysis depth — `agent-retro` analyzes tool result waste, token cost breakdown, and friction per session. `entire dispatch` is a higher-level summary. This is acceptable — deep per-session analysis is the operator's job via `retro-triage`, not an unattended role's job.

## Alternatives considered

**`agent-retro` per role:** Works for Claude Code backend only. Breaks for codex and other backends. Rejected — swarmforge is multi-backend by design.

**Custom per-backend session reader:** Implement JSONL reading for Claude Code, stdout parsing for codex, etc. Maintenance burden grows with each new backend. Rejected — `entire` already solves this.

**No retro at all:** Session stories are lost; systemic improvement requires operator retrospection without data. Acceptable for simple projects; not acceptable for long-running swarms where improvement feedback is valuable. Rejected.

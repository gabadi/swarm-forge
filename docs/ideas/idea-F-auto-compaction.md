# Idea F — Auto-Compaction on Role Worktrees

**Status:** Proposed

## Context

Role agents run unattended for extended periods. The operator typically runs with auto-compaction disabled (personal preference). When that setting propagates to role worktrees, unattended agents run until they overflow their context window — at which point they stop mid-task with no graceful recovery.

Idea A's `/clear` before each job handles between-job context. But within a single job — implementing a complex feature, running mutation across many files — the agent can overflow without ever finishing the job or sending a handoff.

## Decision

At launch, `swarmforge.sh` merges auto-compaction settings into each role's `.claude/settings.local.json`:

```json
{
  "autoCompactEnabled": true,
  "env": {
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "88",
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "200000"
  }
}
```

Merge (not overwrite) — idempotent. If the file already exists (from Idea I's write-deny setup or prior launches), settings are merged in.

**Values:**
- `88` — trips compaction at 88% of the effective window, leaving headroom before hard overflow
- `200000` — pins the effective window to 200K tokens regardless of model size

**Files changed:** `swarmforge/scripts/swarmforge.sh` — new merge step in `write_worktree_permissions` or equivalent.

## Tradeoffs

**What improves:**
- Unattended agents compact gracefully at 88% instead of hitting a hard context overflow
- Operator's own compaction preference doesn't leak into role worktrees
- Fixed window (200K) means behavior is consistent regardless of which model the operator is using

**What disappears:**
- If the operator explicitly wants roles to run without compaction, this overrides that. Considered acceptable — roles are long-running and unattended; overflow is worse than compaction.

**Interaction with Idea A:** Idea A's `/clear` resets conversation history between jobs. Compaction handles within-job overflow. Both are needed — they address different timescales.

## Alternatives considered

**Let operators configure compaction per role in swarmforge.conf:** Adds configuration complexity. The defaults (88%, 200K) are correct for almost all unattended swarm usage. Per-role overrides can be added later if a concrete need arises. Rejected as premature.

**Compact at a higher threshold (95%+):** Less headroom before overflow. At 95%, a large tool result arriving near the threshold could push the agent over before compaction runs. 88% is conservative enough to be safe. Rejected.

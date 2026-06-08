# Idea F — Auto-Compaction on Role Worktrees

**Status:** Decision — Pending Implementation
**Depends on:** None
**Design decisions:** docs/adr/0001-fork-divergence.md § "Design decisions: Idea F"
**Domain vocabulary:** CONTEXT.md — (none)

## What to implement

1. Add a `write_worktree_permissions` function to `swarmforge/scripts/swarmforge.sh` that merges the following into each role worktree's `.claude/settings.local.json` using `bun -e` inline JavaScript (read existing file or start from `{}`; union in settings; write back):
   - `autoCompactEnabled: true`
   - `env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE: "88"`
   - `env.CLAUDE_CODE_AUTO_COMPACT_WINDOW: "200000"`
2. Call `write_worktree_permissions "$worktree_path"` from `prepare_worktrees`, after `write_worktree_notify_wrapper`.

---

## Files changed

| Branch | File | Change |
|--------|------|--------|
| `main` | `swarmforge/scripts/swarmforge.sh` | Add `write_worktree_permissions`; call from `prepare_worktrees` |

# Idea I — swarmforge/ Write Deny on Role Worktrees

**Status:** Proposed

## Context

Role agents run with `--permission-mode auto`, which allows them to edit any file they choose. Nothing prevents a role from editing its own prompt (`swarmforge/roles/coder.prompt`), its own settings (`swarmforge/constitution/workflow.prompt`), or its own `.claude/settings.local.json`.

A role editing its own prompt is silent drift: the change affects future behavior but is not tracked as a fork divergence, is not reviewed, and may conflict with upstream on the next rebase. A role lifting its own lock (editing `settings.local.json` to remove a deny rule) defeats any access control applied at launch.

This failure mode is subtle — a role agent will not maliciously edit its prompt, but it might do so while trying to "help" (e.g., adding a note about a project convention it discovered, or adjusting a rule it thinks is wrong).

## Decision

At launch, `swarmforge.sh` merges a `permissions.deny` block into each role's `.claude/settings.local.json`:

```json
{
  "permissions": {
    "deny": [
      "Edit(swarmforge/**)",
      "Write(swarmforge/**)",
      "MultiEdit(swarmforge/**)",
      "NotebookEdit(swarmforge/**)",
      "Edit(.claude/settings.local.json)",
      "Write(.claude/settings.local.json)"
    ]
  }
}
```

Merge (not overwrite) — idempotent. Applied after Idea F's auto-compaction settings in the same merge step.

Covering `settings.local.json` itself is critical: without it, a role could edit the file to remove its own deny rules, lifting the lock entirely.

The launcher (running in the main shell, not the role worktree) seeds the `settings.local.json` from the host shell before the deny takes effect — so the deny never blocks the setup step itself.

**Files changed:** `swarmforge/scripts/swarmforge.sh` — new deny merge in `write_worktree_permissions`.

## Tradeoffs

**What improves:**
- Roles cannot edit their own prompts, constitution files, or settings — drift is structurally prevented
- The deny is hard (`--permission-mode auto` grants; `deny` blocks regardless)
- Self-lock-lifting is prevented by covering `settings.local.json`

**What disappears:**
- A role that discovers a genuine bug in its own prompt cannot fix it autonomously — it must route the finding to the operator. This is intentional: prompt changes are fork divergences and must go through the documented process.

## Alternatives considered

**Prompt rule ("do not edit your own prompt"):** Agents can ignore prompt rules, especially after compaction drops context. A `deny` hard-blocks regardless of instruction state. Rejected as insufficient.

**Read-only worktrees via git:** Making the worktree's `swarmforge/` subtree read-only at the filesystem level would block all edits, including legitimate ones by the operator. Too blunt. Rejected.

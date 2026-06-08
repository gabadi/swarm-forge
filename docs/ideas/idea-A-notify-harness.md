# Idea A — Notify Harness

**Status:** Decision — Pending Implementation  
**Depends on:** Idea B (bundle must be cached at `.swarmforge/prompts/<role>.md` before delivery sequence runs)  
**Design decisions:** `docs/adr/0001-fork-divergence.md` § "Design decisions: Idea A"  
**Domain vocabulary:** `CONTEXT.md`

## What to implement

Replace the prompt-driven queue with a shell harness. Remove `pending-messages/` directory and all its constitution rules. The harness owns all logbook writes; the agent writes nothing to `logbook.json`.

---

## 1. `swarmforge/scripts/swarmforge.sh` (on `main`)

### 1a. `write_notify_script`

Rewrite the generated `notify-agent.sh` with the following behaviour:

1. Validate sender's worktree tree is clean; exit with hint if dirty
2. Read `git rev-parse HEAD` from sender's worktree; append `[handoff] merge-commit=<hash>` to the message
3. Append `sent` entry to sender's `logbook.json` — fields: `status`, `target`, `message`, `hash`, `timestamp`
4. Append `executed` entry to sender's `logbook.json` — fields: `status`, `timestamp`
5. Read receiver's `logbook.json`; find last entry whose status is `executing` or `executed` (ignore `sent`/`pending` for this check)
6. If last terminal status is `executed` or logbook is empty → run **delivery sequence** immediately
7. If last terminal status is `executing` → append `pending` entry to receiver's `logbook.json` — fields: `status`, `message`, `hash`, `timestamp`

Never return an error for "already queued." Always append.

### 1b. New `write_stop_hook` function

Called from `launch_role` for each role. Writes a Stop hook into `<worktree>/.claude/settings.local.json` (merge, do not overwrite unrelated keys).

The Stop hook shell script (bake in `LOGBOOK`, `BUNDLE`, `DISPLAY_NAME`, `MUX_TARGET`, `WORKTREE_PATH` at launch time):

1. Read own `logbook.json`
2. Find last entry with status `executing` or `executed`
3. If `executed`: find first `pending` entry that appears after the last `executing` entry in the log
4. If found: run **delivery sequence** with that entry's message and hash
5. Otherwise: exit 0

### 1c. Delivery sequence (shared shell function, called by both notify-agent.sh and Stop hook)

Arguments: receiver mux target, receiver display name, receiver worktree path, receiver logbook path, receiver bundle path, message content, commit hash.

Steps:
1. Append `executing` entry to receiver's `logbook.json` — fields: `status`, `timestamp`
2. `git reset --hard <hash>` in receiver's worktree
3. Send `/clear` to receiver's terminal (via `cmux send` or `tmux send-keys`)
4. Sleep 1s
5. Send `/rename SwarmForge <display-name>` to receiver's terminal
6. Send contents of `<bundle-path>` to receiver's terminal
7. Send message content to receiver's terminal

---

## 2. Role prompts on `four-pack` and `six-pack`

Remove all references to:
- `pending-messages/` directory
- Instructions to write `executing`, `executed`, or any logbook entry
- Instructions to process queued message files

The agent's only harness obligation is: call `notify-agent.sh <target> "<message>"` when the task is complete (after retro). The harness handles all state transitions.

---

## Files changed

| Branch | File | Change |
|--------|------|--------|
| `main` | `swarmforge/scripts/swarmforge.sh` | Rewrite `write_notify_script`; add `write_stop_hook`; add `deliver` shared function |
| `four-pack` | `swarmforge/roles/*.prompt` | Remove pending-messages rules and logbook write instructions |
| `six-pack` | `swarmforge/roles/*.prompt` | Same |

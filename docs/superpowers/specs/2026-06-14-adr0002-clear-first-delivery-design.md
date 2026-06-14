# ADR 0002 Clear-First Delivery Engine — Design Spec

**Date:** 2026-06-14
**Branch:** feat/fork-divergences-main → PR #31
**Status:** Approved for TDD implementation

## Problem

ADR 0002 specifies a clear-first delivery engine for claude-backend roles. When the engine was designed, the cmux multiplexer provided the Stop hook. When cmux was dropped, the engine was lost. The executing-fields pending item was addressed (commit `7af75c3`) but the engine itself was never built. Upstream types each handoff directly into the terminal with no context clear; the fork requires `/clear` → re-inject bundle → deliver task.

## Scope

Claude backend only. `codex`/`grok`/`copilot` keep upstream delivery (direct `notify-agent.sh` tmux path) unchanged. The `claude`/`codex` choice is a per-role config knob (ADR 0012); this ADR only covers the claude path.

## Shared State

**Pending queue:** `.swarmforge/handoffs/queue/pending/<role>/`
- Files named `<priority>-<timestamp>-<stream>-<seq>.txt`
- Content: full protocol message (same envelope `send-handoff.sh` builds)
- Written by sender; drained by Stop hook

**Busy marker:** `.swarmforge/<role>.busy`
- Present = role is executing; absent = idle and accepting delivery
- Created atomically with zsh `noclobber` (`set -C; > file`); only the winner delivers

## Delivery Function (`handoff-lib.sh`)

```
handoff_clear_first_deliver <project_dir> <role> <message_file>
```

1. Look up target tmux session from `.swarmforge/sessions.tsv`
2. Read socket from `.swarmforge/tmux-socket`; also try `TMUX` env var fallback (same as `notify-agent.sh`)
3. Send `/clear\n` to tmux session; `sleep 1`
4. If `.swarmforge/prompts/<role>.md` exists: send its content + C-m + C-j; `sleep 0.5`
5. Send protocol message content + C-m + C-j

**No logbook write here.** The delivery function is called from both the sender (idle path) and the Stop hook (busy path). The sender's `$PWD` is the wrong worktree for the receiver's logbook. Instead:
- **Stop hook writes `executing`** to `$PWD/logbook.jsonl` (correct — hook runs in receiver's worktree) before calling this function
- **Idle path** gets its `executing` entry from `complete-handoff.sh` (called by the agent after receipt) — same as upstream

## Idle Path (`send-handoff.sh`)

After building the protocol message, replace the direct `notify-agent.sh <target>` call with:

1. Look up target agent type from `.swarmforge/sessions.tsv` (agent column)
2. If not `claude`: fall back to existing `notify-agent.sh "$TARGET" --file "$ARCHIVE_FILE"` (unchanged)
3. If `claude`:
   a. Write message to pending queue dir
   b. Attempt atomic `set -C; > .swarmforge/<target>.busy`
   c. If succeeded (was idle): call `handoff_clear_first_deliver` → role is now busy
   d. If failed (already busy): message stays in pending queue; Stop hook drains it

## Busy Path (`swarm-stop.sh` — new Stop hook)

Receives JSON on stdin from Claude Code (`session_id`, `cwd`, `hook_event_name`).

1. Read `SWARMFORGE_ROLE`; if unset, exit 0 (not a swarmforge role)
2. Derive `project_dir` from `cwd` field in stdin JSON (or git fallback)
3. Re-check pending queue — **do NOT noclobber here** (in the normal busy-path the marker is already set from the delivery that started this task; noclobber would cause the hook to bail and never drain the queue)
4. If queue non-empty: `touch .busy` (ensure busy, idempotent), write `executing` logbook entry to `$PWD/logbook.jsonl` (hook runs in receiver's worktree), call `handoff_clear_first_deliver`, remove pending file, exit 0 (marker stays = busy)
5. If queue empty: delete `.busy` marker (role goes idle), exit 0

The ADR's "re-check before declaring idle" race closure: between the `ls` returning empty and the `rm .busy`, a sender may have written to the pending dir. That sender's `noclobber` wins (`.busy` was just deleted) and delivers immediately. No message is lost.

## Settings Wiring (`write_worktree_settings`)

Third parameter: `stop_script` (absolute path to `swarm-stop.sh`).

Python RMW adds to `.claude/settings.local.json`:
```json
{
  "hooks": {
    "Stop": [{"matcher": "", "hooks": [{"type": "command", "command": "<abs-path-to-swarm-stop.sh>"}]}]
  }
}
```

Called for ALL claude roles in `launch_role` (not just advisor-having ones):
```sh
write_worktree_settings "$role_worktree" "$role_advisor" "$role_script_dir/swarm-stop.sh"
```

Non-claude roles: existing call pattern (advisor only, no stop script).

## Launch Change (PR comment 2 resolution)

Drop the positional `"$(cat '$prompt_file')"` from the claude `launch_cmd`. The session starts with `--append-system-prompt-file` (system prompt, survives `/clear`), then waits idle. The first task arrives via clear-first delivery which re-injects the bundle as the first conversational message.

## Presence Ping Exclusion

Upstream's startup "I'm awake" ping uses `message type: presence`. The Stop hook must not deliver presence messages via the clear-first path. In practice: the pending queue only contains messages put there by `send-handoff.sh` (which only handles `handoff` and `resend-request` types). Presence pings are not routed through `send-handoff.sh`, so they never enter the pending queue. No special check needed.

## Test Checkpoints (TDD)

1. `handoff_clear_first_deliver` — mock tmux, verify call sequence: clear → sleep 1 → bundle → message (no logbook write in this function)
2. `send-handoff.sh` idle path — claude target, no `.busy`: pending file written, `.busy` created, delivery called
3. `send-handoff.sh` busy path — claude target, `.busy` pre-exists: pending file written, no delivery
4. `send-handoff.sh` non-claude — codex target: no pending file, `notify-agent.sh` called directly
5. `swarm-stop.sh` queue non-empty — pending file present: executing entry written to logbook, delivery called, pending file removed, `.busy` stays
6. `swarm-stop.sh` queue empty — no pending file: `.busy` deleted
7. `swarm-stop.sh` with queue non-empty AND `.busy` already set (normal busy-path case) — hook delivers, does NOT bail on pre-existing marker
8. `write_worktree_settings` with stop_script — resulting JSON has `hooks.Stop` entry with correct command

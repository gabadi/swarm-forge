# Idea A — Notify Harness

**Status:** Proposed  
**Depends on:** Idea B (prerequisite — /clear requires the bundle to be in system prompt)

## Context

The current message delivery system is entirely honor-system and prompt-driven. `notify-agent.sh` fires `cmux send` or `tmux send-keys` — the message is injected directly into the agent's terminal input with no buffering, acknowledgment, or retry.

If the receiving agent is busy mid-task when the message arrives, the agent is supposed to:
1. Notice it arrived while busy
2. Save it as a file in `pending-messages/PP-YYYYMMDD-HHMMSS-source.txt`
3. Finish the current job
4. Process queued files in sorted order
5. Delete each file after processing
6. Log everything to `logbook.json`

None of this is mechanically enforced. Failure modes:
- Agent is mid-context, message lands unnoticed
- Agent partially processes the message, gets distracted
- No acknowledgment back to sender — sender never knows if delivery succeeded
- No retry — lost message is gone
- Priority ordering is only in the filename, enforced only by the agent reading the directory in sorted order

Additionally, agents carry state across jobs within a session. Compaction during a long job can drop prior constitution context. A compacted agent starting a new handoff has degraded instructions.

## Decision

Replace the prompt-driven queue entirely with a shell harness. The agent-managed `pending-messages/` directory and all its constitution rules are removed.

### Harness queue (sender side)

`notify-agent.sh` is called by the sending role. It:
1. Validates the tree is clean (refuse if dirty, with a hint)
2. Reads `git rev-parse HEAD` from the sender's worktree and appends `[handoff] merge-commit=<hash>` to the message
3. Writes a `sent` entry to the sender's `logbook.json` with the target role, message, and commit hash
4. Checks if the target role is idle by reading the last relevant entry in the receiver's `logbook.json`
5. If idle (last entry is `executed` or no entry exists): executes the delivery sequence immediately
6. If busy (last entry is `executing`): exits — the Stop hook will deliver when the agent finishes

### logbook.json statuses

Each role maintains its own `logbook.json` in its assigned worktree.

**Sender side** (written by `notify-agent.sh`):
- `sent` — message written, delivery attempted or queued

**Receiver side** (written by the receiver agent):
- `pending` — message arrived while the agent was mid-job; queued for processing
- `executing` — agent started working on this job
- `executed` — job complete: downstream handoff sent AND `agent-retro` finished. Must be written after retro, not before — the Stop hook reads this as the signal to deliver the next message.

### Delivery sequence

When delivering a message (whether immediately or from the Stop hook):
1. Send `/clear` to the target agent's terminal (clears conversation history, system prompt survives)
2. Re-send the full resolved prompt bundle (constitution + role — same as at launch, see Idea B)
3. Send the queued message

This makes each job stateless: the agent starts from a clean context floor with full instructions, then receives exactly one handoff message.

### Idle signal (Stop hook)

A `Stop` hook in each role's `.claude/settings.local.json` fires when the agent stops responding. The hook:
1. Reads the receiver's own `logbook.json` — checks if the last relevant entry is `executed`
2. If `executed`: job is complete — check if sender-side logbooks have any `sent` entry targeting this role not yet delivered; if so, run the delivery sequence
3. If `executing` or `pending`: mid-job pause — do nothing

### Receiver side

Receiver resets to the commit hash in the `[handoff]` trailer — not the branch tip. This avoids phantom conflicts on squash-to-main repos where long-lived role branches carry pre-squash history.

## Tradeoffs

**What improves:**
- Delivery is durable — message written to logbook before any terminal send
- No message can be lost to agent inattention
- Each job starts from a clean context floor — eliminates inter-job state leakage
- Job-complete discriminator is logbook-native — no new files or directories
- Acknowledgment is implicit — receiver's `executed` status confirms completion

**Files changed:**
- `main`: `swarmforge/scripts/swarmforge.sh` — Stop hook writing at launch, notify-agent.sh generation with git hash
- `four-pack` + `six-pack`: role prompts — `executing`/`executed` logbook status steps in lifecycle close-out

**What gets more complex:**
- `swarmforge.sh` must write the Stop hook into each role's `settings.local.json` at launch
- The harness reads across worktree logbooks — requires knowing all worktree paths (available from `swarmforge.conf`)

**What disappears:**
- `pending-messages/` directory and all its constitution rules — simpler prompt
- New `.swarmforge/queue/` and `.swarmforge/state/` directories — not needed; logbook carries all state

## Alternatives considered

**Sentinel file as job-complete discriminator:** Each role's close-out step writes a file before going idle. Rejected — logbook `executed` status is the natural close-out signal; a separate file duplicates the same information.

**Harness checks whether `notify-agent.sh` was called since last delivery:** Works for most roles but has no equivalent for the terminal role (which notifies specifier to restart). Rejected — logbook status is role-agnostic and already present.

**Keep the prompt-driven queue, add mechanical enforcement around it:** Would require shell wrappers that watch the `pending-messages/` directory and re-inject messages. Complex and still doesn't solve the inter-job context problem. Rejected — the harness solves both problems at once.

**Full agent restart instead of /clear:** Kill and restart the agent process for each job. Cleaner (no conversation history at all) but adds cold-start latency and loses tool authentication state on some backends. Rejected — `/clear` achieves the same context-floor effect with no latency or auth cost, since system prompt (with full bundle from Idea B) survives the clear.

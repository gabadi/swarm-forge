# Idea A — Notify Harness

**Status:** Proposed  
**Depends on:** Idea B (prerequisite — /clear requires the bundle to be in system prompt)

## Context

The current message delivery system is entirely honor-system and prompt-driven. `notify-agent.sh` fires `tmux send-keys` or `cmux send` — the message is injected directly into the agent's terminal input with no buffering, acknowledgment, or retry.

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
3. Writes the message to the harness queue for the target role: `.swarmforge/queue/<target-role>/PP-YYYYMMDD-HHMMSS-<source>.txt`
4. Checks if the target role is idle (reads `.swarmforge/state/<target-role>`)
5. If idle: executes the delivery sequence immediately
6. If busy: exits — the Stop hook will deliver when the agent finishes

### Delivery sequence

When delivering a queued message (whether immediately or from the Stop hook):
1. Mark target as busy: write `.swarmforge/state/<target-role> = busy`
2. Send `/clear` to the target agent's terminal (clears conversation history, system prompt survives)
3. Re-send the full resolved prompt bundle (constitution + role — same as at launch, see Idea B)
4. Send the queued message
5. Delete the delivered queue file

This makes each job stateless: the agent starts from a clean context floor with full instructions, then receives exactly one handoff message.

### Idle signal (Stop hook)

A `Stop` hook in each role's `.claude/settings.local.json` fires when the agent stops responding. The hook:
1. Checks if a handoff was sent since the last delivery (job-complete discriminator — see Open questions)
2. If job complete: mark role as idle, check queue for pending messages, deliver next if found
3. If mid-job pause: do nothing

### Receiver side

Receiver resets to the commit hash in the `[handoff]` trailer — not the branch tip. This avoids phantom conflicts on squash-to-main repos where long-lived role branches carry pre-squash history.

## Tradeoffs

**What improves:**
- Delivery is durable — message written to disk before any terminal send
- No message can be lost to agent inattention
- Each job starts from a clean context floor — eliminates inter-job state leakage
- Priority ordering is enforced by the harness, not the agent
- Acknowledgment is implicit — the queue file is deleted only after delivery

**What gets more complex:**
- `swarmforge.sh` must write the Stop hook into each role's `settings.local.json` at launch
- The harness needs a reliable job-complete signal (see Open questions)
- State files (`.swarmforge/state/`, `.swarmforge/queue/`) are new runtime state to manage

**What disappears:**
- `pending-messages/` directory and all its constitution rules — simpler prompt
- `logbook.json` entries for queued messages (the harness owns the queue; logbook remains for received/sent entries only)

## Open questions

**Job-complete discriminator:** The Claude Code Stop hook fires per-turn (every time the agent finishes a response), not only when the full job is done. The harness needs to distinguish "mid-job pause" from "job complete — ready for next message." 

Candidates:
- Agent's close-out step writes a sentinel file before going idle (requires adding a close-out step to every role prompt — small prompt diff)
- Harness checks whether `notify-agent.sh` was called since the last delivery (handoff sent = job done)
- Harness checks for a pattern in tmux/cmux pane output indicating idle prompt

The sentinel-file approach is most reliable and least fragile. The handoff-sent check is second. Pane output pattern is fragile.

## Alternatives considered

**Keep the prompt-driven queue, add mechanical enforcement around it:** Would require shell wrappers that watch the `pending-messages/` directory and re-inject messages. Complex and still doesn't solve the inter-job context problem. Rejected — the harness solves both problems at once.

**Full agent restart instead of /clear:** Kill and restart the agent process for each job. Cleaner (no conversation history at all) but adds cold-start latency and loses tool authentication state on some backends. Rejected — `/clear` achieves the same context-floor effect with no latency or auth cost, since system prompt (with full bundle from Idea B) survives the clear.

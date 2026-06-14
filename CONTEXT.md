# SwarmForge Fork

A permanent fork of `unclebob/swarm-forge` (rationale in `docs/adr/`). This glossary holds only terms whose fork-specific meaning is already settled; terms are added as decisions are made, not in advance.

## Language

**Idle gate**:
The rule that a role does nothing until it receives a handoff — no startup work, scanning, installing, or self-assigned tasks. The single line is "Wait for a handoff. Do not act without one."
_Avoid_: startup guard, wait condition

**Ready notification** (presence signal):
The startup "I'm awake" message each role sends to the specifier. Informational only — it tells the operator the role launched. Stamped a distinct `presence` type and excluded from the _Delivery sequence_; in the fork's idle model readiness is implicit (a role at idle with an empty queue is ready).
_Avoid_: awake handoff, ready handoff

**Delivery sequence**:
The fork's Stop-hook steps that start a work handoff on an idle receiver: `/clear` → re-inject the role bundle (`codex`/`grok` only) → send the task message. Runs only for work handoffs, never for presence pings. (Upstream instead types the message straight into the terminal with no clear.)
_Avoid_: inject, dispatch

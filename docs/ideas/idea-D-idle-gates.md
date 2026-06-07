# Idea D — Role Idle Gates

**Status:** Proposed

## Context

Upstream's role prompts include startup directives that fire when the agent launches:

- Coder: "At startup, make sure the acceptance pipeline … is in place" with sub-bullets for installation
- Architect: "At startup, install the language mutation tool…" and "At startup, install the language DRY tool…"
- Refactorer: "At startup, install the language CRAP and DRY tools…"

These were designed for a greenfield repo where tools are not yet installed. On a mature project where these tools are already present (e.g. an existing Addi repo), they fire unnecessarily at every cold launch — scanning the whole codebase, reinstalling tools that are already installed, consuming tokens and time with no output.

Upstream also has no explicit idle gate: a role launched without a handoff will begin looking for work to do (scanning the repo, running verification, applying its role rules proactively). This is destructive on a mature codebase.

## Decision

Add an explicit idle gate to each role prompt:

> Act only on an explicit handoff. No handoff — including a cold launch or work you could find yourself — means idle: wait for a message. Do not scan, install, verify, or apply role rules without a handoff.

Remove the startup install directives. Tool installation belongs in project setup (see Idea K), not in role startup.

**Files changed:**
- `four-pack` + `six-pack`: `swarmforge/roles/*.prompt` — idle gate added, startup install directives removed

**Diff from upstream:** Small. The idle gate is additive. The startup directive removal is a drop of lines that are no-ops on mature projects. Minimal divergence.

## Tradeoffs

**What improves:**
- Cold launches are safe on mature projects — no proactive scanning or installing
- Roles wait cleanly for a handoff, consistent with how the harness (Idea A) delivers work
- Removes install overhead from every startup

**What disappears:**
- Automatic tool installation on greenfield projects — operators must ensure tools are installed before starting the swarm (this belongs in Idea K's setup step)

## Alternatives considered

**Keep startup directives, guard them with an existence check:** Add "if the tool is already installed, skip." Prompt verbosity increases; still fires a check on every startup. Rejected — Idea K handles setup once; per-launch checks are redundant.

**Keep proactive scanning, gate only installation:** Roles would still scan the repo on cold launch, applying their quality rules to whatever they find. On a mature codebase this produces unsolicited refactoring or mutation runs. Rejected.

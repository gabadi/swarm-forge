# Idea B — Prompt Bundle Inlining at Launch

**Status:** Proposed  
**Required by:** Idea A (prerequisite — /clear re-injection only works if bundle is in system prompt)

## Context

Upstream delivers role instructions by writing two lines into each agent's instruction file:

```
Read swarmforge/constitution.prompt and follow its instructions recursively.
Read swarmforge/roles/<role>.prompt and follow its instructions recursively.
```

The agent is expected to read those files at startup and follow any nested `@file` references. In practice agents skip or partial-read this recursion — the constitution delegates to three subordinate files (`project.prompt`, `engineering.prompt`, `workflow.prompt`), and agents frequently miss one or more. Rules that exist in writing are violated because they never arrive in the agent's context.

Additionally, Idea A's `/clear` + re-injection sequence requires the full instruction bundle to survive `/clear`. In Claude Code, `/clear` clears conversation history but the system prompt survives. For this to work, the bundle must be in the system prompt — not in the conversation as a read instruction.

## Decision

At launch, `swarmforge.sh` resolves the full prompt bundle for each role and writes it as the system prompt:

1. Read `swarmforge/constitution.prompt`
2. Follow every `swarmforge/*.prompt` reference in order (breadth-first, dedup)
3. Read `swarmforge/roles/<role>.prompt`
4. Concatenate all files in resolution order into one flat text file
5. Pass to the agent via `--append-system-prompt-file <bundle-file>` (for `claude`) or equivalent

No XML envelope — flat concatenation. The resolved bundle is cached at `.swarmforge/prompts/<role>.md` so Idea A's re-injection reads the same file without re-resolving.

Files changed: `swarmforge/scripts/swarmforge.sh` — new `resolve_prompt_bundle` and `write_agent_instruction_file` functions.

## Tradeoffs

**What improves:**
- Rules arrive atomically before the first turn — no agent can miss a constitution file
- `/clear` preserves the bundle — agents re-read instructions after clear without any re-injection needed for the system prompt portion (Idea A re-injects the cached bundle as a message to ensure it lands in conversation context too)
- Deterministic precedence — constitution files always arrive in the same order

**What gets more complex:**
- The resolved bundle is a snapshot at launch time; if a prompt file is edited mid-session the agent does not see the update (requires restart)
- The cached bundle at `.swarmforge/prompts/` is new runtime state

**What disappears:**
- The `Read swarmforge/constitution.prompt...recursively` instruction lines — prompt is simpler

## Alternatives considered

**XML envelope (melech D22 approach):** Wraps each file in `<file path="...">...</file>` inside an outer `<swarmforge_agent_context>` envelope. Adds structure no agent behavior depends on. Flat concatenation achieves the same delivery guarantee with less complexity. Rejected.

**Keep recursive reads, add enforcement:** Add a verification step where the harness confirms the agent echoed back key rules at startup. Fragile — agent could echo rules without having internalized them. Does not solve the `/clear` re-injection problem. Rejected.

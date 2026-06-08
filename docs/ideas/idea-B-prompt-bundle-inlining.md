# Idea B — Prompt Bundle Inlining at Launch

**Status:** Decision — Pending Implementation  
**Required by:** Idea A (delivery sequence reads bundle cache at `.swarmforge/prompts/<role>.md`)  
**Design decisions:** `docs/adr/0001-fork-divergence.md` § "Design decisions: Idea B"  
**Domain vocabulary:** `CONTEXT.md` — Prompt bundle, Bundle cache

## What to implement

At launch, `swarmforge.sh` resolves the full prompt bundle for each role and writes it as the system prompt:

1. BFS from `swarmforge/constitution.prompt`, grepping each file for paths matching `swarmforge/[A-Za-z0-9_./-]+\.prompt` — deduped, in discovery order
2. BFS from `swarmforge/roles/<role>.prompt` the same way
3. Merge: constitution bundle first, then any role-bundle files not already present
4. Wrap in XML envelope: `<swarmforge_agent_context role="<role>">` with an `<instructions>` preamble and one `<file path="...">` block per resolved file. Preamble tells the agent the bundle is pre-resolved — it must not open prompt files itself.
5. Write to `.swarmforge/prompts/<role>.md` (bundle cache)
6. Deliver to the agent: `--append-system-prompt-file <bundle-file>` for `claude`; `$(cat <bundle-file>)` as the initial message for other agents (codex, grok, etc.)

---

## Files changed

| Branch | File | Change |
|--------|------|--------|
| `main` | `swarmforge/scripts/swarmforge.sh` | New `resolve_prompt_bundle` function; rewrite `write_agent_instruction_file` to use it |

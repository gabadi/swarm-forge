# Idea G — Per-Technology Engineering File

**Status:** Proposed  
**Open question:** How does install-time technology selection work?

## Context

The current `swarmforge/constitution/engineering.prompt` contains a multi-language tool table covering Go, Clojure, and Java — one row per language mapping the generic role-prompt references ("the language mutation tool", "the language DRY tool") to concrete commands for each language.

Problems:
- A project uses one language. Agents read three languages' worth of tool mappings and must infer which row applies to them. This is implicit and error-prone.
- Adding a new language (TypeScript, Rust, Python) requires editing the shared file on both runnable branches.
- The table grows unbounded as languages are added.

## Decision

Replace the multi-language table with a project-specific `engineering.prompt` that contains only the relevant language's row. At install time (Idea K's setup step), the operator selects the project language and the setup writes `engineering.prompt` with only that language's tool mappings.

The role prompts keep upstream's generic phrasing ("the language mutation tool", "the language DRY tool") — only the mapping table changes. One file, one language, no ambiguity.

**Source templates:** A `swarmforge/engineering-templates/` directory on `main` (or on the runnable branches) holds one template per supported language:
- `engineering-go.prompt`
- `engineering-clojure.prompt`
- `engineering-typescript-bun.prompt`
- etc.

At install, the setup copies the relevant template as `swarmforge/constitution/engineering.prompt`.

**Files changed:**
- `swarmforge/constitution/engineering.prompt` becomes a generated, project-specific file (not tracked in the runnable branch — generated at install time)
- New `swarmforge/engineering-templates/` directory on `main` with one template per language

## Open questions

**How does install-time selection work?** Two options:

1. **`/enabling-swarm-forge` skill asks the question** — the install skill prompts "what language?" and copies the right template. Simple, requires one interactive question at install time.

2. **`swarmforge.conf` has a `language` field** — the conf drives selection automatically with no interactive prompt. But this adds a new field to the conf format (upstream doesn't have it) and requires Idea K's preflight to read and act on it.

Option 1 is simpler for the first implementation. Option 2 is better for automated/headless setup. This question must be resolved before implementing.

**What if a project uses multiple languages?** Rare but possible. For now: choose the dominant language. If multi-language support is needed later, the setup can concatenate multiple templates.

## Alternatives considered

**Keep the multi-language table, rely on agents to select the right row:** Current behavior. Works if agents reliably select the right row — but they must infer the language from the project, which is an implicit step. Rejected — ambiguity in tool mapping is a real source of agent error.

**One engineering.prompt per language as a committed file in the runnable branches:** The runnable branch ships all language files; the constitution delegates to the right one based on a `language` declaration in `project.prompt`. Requires prompt logic for selection; adds multiple files to maintain per branch. Rejected — the install-time copy approach keeps the constitution simple.

# Idea G — Per-Technology Engineering File

**Status:** Proposed

## Context

The current `swarmforge/constitution/engineering.prompt` contains a multi-language tool table covering Go, Clojure, and Java — one row per language mapping the generic role-prompt references ("the language mutation tool", "the language DRY tool") to concrete commands for each language.

Problems:
- A project uses one language. Agents read three languages' worth of tool mappings and must infer which row applies to them. This is implicit and error-prone.
- Adding a new language requires editing the shared file on both runnable branches.
- The table grows unbounded as languages are added.

## Decision

Replace the multi-language table with two files per supported language on `main`:

- `swarmforge/engineering-templates/engineering-<lang>.prompt` — tool usage commands only; what agents read during jobs
- `swarmforge/engineering-templates/setup-<lang>.prompt` — self-contained setup instructions; when given to an agent, installs the required tools and writes `engineering.prompt` into the target project

The runnable branches (`four-pack`, `six-pack`) carry **no** `engineering.prompt`. It is always generated at install time for each target project.

### Install flow

The user is told to give their agent the raw URL of the setup prompt for their language:

```
https://github.com/gabadi/swarm-forge/raw/main/swarmforge/engineering-templates/setup-<lang>.prompt
```

The agent fetches it, follows the instructions, installs the required tools, and writes `engineering-<lang>.prompt` as `swarmforge/constitution/engineering.prompt` in the target project. No skill dependency, no scripts — the agent handles OS differences by reading the prompt.

This is the same fetch-from-main pattern the `swarm` script already uses for shared scripts.

### Why no install script

Install steps vary by OS and package manager. A prompt is OS-agnostic — the agent reads the intent and applies the right commands for the current environment.

**Files changed:**
- New `swarmforge/engineering-templates/` on `main` — one `engineering-<lang>.prompt` + `setup-<lang>.prompt` per supported language
- `swarmforge/constitution/engineering.prompt` removed from runnable branches — generated per project at install

## Alternatives considered

**Keep the multi-language table, rely on agents to select the right row:** Current behavior. Agents must infer the language from the project — implicit and error-prone. Rejected.

**Install script per language:** OS-specific and fragile. A prompt handled by the agent is more portable. Rejected.

**One engineering.prompt per language committed to the runnable branches:** Multiple files to maintain per branch; runnable branches grow with each new language. Rejected — templates on `main` keep runnable branches clean.

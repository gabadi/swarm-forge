# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Fork Divergence

This is a permanent fork of `unclebob/swarm-forge`. Before touching scripts, constitution files, or rebasing against upstream, read [`docs/adr/0001-fork-divergence.md`](docs/adr/0001-fork-divergence.md). It documents which changes are permanent, which are temporary, and the exact rebase procedure.

## Installing SwarmForge into a project

Use `/enabling-swarm-forge`. It reads this fork live and walks through branch selection, role configuration, install, and a pilot slice.

## Branch Model

**`main` is documentary only.** It holds shared operational scripts (`swarmforge/scripts/`) and documentation. Do not add role prompts or swarm configs here.

**`four-pack` and `six-pack` are the runnable branches.** Each carries its own `swarmforge/swarmforge.conf`, constitution, and role prompts. Changes to role behavior, constitution rules, or workflow prompts belong on one or both of these branches — not on `main`.

When fixing something in the constitution or role prompts, check whether the fix applies to both runnable branches and apply it to each.

## Repository Layout

```
swarmforge/scripts/     # shared shell scripts (lives on main, copied to projects at runtime)
examples/               # documentation references only — do not edit to fix real behavior
docs/adr/               # architecture decision records for this fork
```

The runnable branches (`four-pack`, `six-pack`) add:

```
swarmforge/swarmforge.conf          # role → agent → worktree mapping
swarmforge/constitution.prompt      # entry point, delegates to constitution/ files
swarmforge/constitution/
  project.prompt
  engineering.prompt
  workflow.prompt                   # handoff and logbook rules live here
swarmforge/<role>.prompt            # one file per role in swarmforge.conf
```

## logbook.json

`logbook.json` is **gitignored and local per worktree**. Agents maintain it for handoff history but must never commit it.

## swarmforge.conf Format

```conf
window <role> <agent> <worktree>
```

First window is the cleanup window (closing it tears down the swarm). A worktree of `master` means the role runs in the main working directory.


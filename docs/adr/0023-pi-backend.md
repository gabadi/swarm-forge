---
status: accepted
---

# pi as a first-class agent backend

SwarmForge launches roles against a configured agent CLI. The fork already supports `claude`, `codex`, `copilot`, and `grok`. This ADR adds `pi` (`@earendil-works/pi-coding-agent`) as a first-class backend with the same capabilities the fork gives Claude Code, adapting to pi's different configuration surface.

## Decisions

### `pi` is whitelisted in `parse-config`; operators write `pi` in the agent column

`swarmforge.bb :: parse-config` accepts `pi` alongside `claude`/`codex`/`copilot`/`grok`. No new config file: a six-pack/four-pack/two-pack operator changes `codex` → `pi` on the windows they want. Mixed-backend swarms work with no conf change.

### Launch command adapts to pi's CLI

`swarmforge.bb :: launch-command` gains a `pi` branch:

```
pi --append-system-prompt <pointer-file> --approve --extension <swarmforge-pi.ts> -n 'SwarmForge <Display>' <extra-args>
```

- `--append-system-prompt <file>` — pi resolves the arg as a file path first, then literal text (verified in `dist/core/resource-loader.js :: resolvePromptInput`). It is the exact analogue of `claude --append-system-prompt-file`.
- `--approve` — load `.pi/` + `.agents/` resources unattended (pi non-interactive modes do not show a trust prompt; without `--approve` or a saved decision, project resources are skipped).
- `--extension` — loads the bundled `swarmforge-pi` extension (see below).
- No `--permission-mode`. pi has no permission-prompt system; it is autonomous by default. The fork's Claude allowlist safety property is **not** replicated for pi (decision: ignore — see "Permission model" below).

### `.agents/skills/` is the single real skill dir; claude sees it via a directory symlink

`install-skills!` writes local skills (`agent-retro`, `setup-swarm`) + pinned `entire`/`mattpocock` tarballs into `.agents/skills/` (was `.claude/skills/`). `write-persona-skill-file!` writes `.agents/skills/swarm-persona/SKILL.md` (was `.claude/skills/...`). `link-skills!` (formerly `link-curator-skills!`) creates **one directory-level symlink** `.claude/skills` → `../.agents/skills`, replacing the per-skill symlink loop. pi auto-discovers `.agents/skills/` from cwd + ancestors, so it needs no symlink; the symlink is harmless for pi and keeps one code path for both backends. This unifies the curator contract (six-pack `curator.prompt` already treats `.agents/skills/<name>/` as canonical) with the launcher's install.

`AGENTS.md` is removed from the swarm-persona bundle body: pi loads it natively via `loadContextFileFromDir`. `.agents/roles/<role>.md` stays in the bundle (role-specific, not auto-loaded).

### `.claude` gitignore entries are removed completely

The repo `.gitignore` no longer carries `.claude/*` or `!.claude/skills/`, and `setup-swarm` no longer appends `.claude/skills/swarm-persona/`. SwarmForge stops managing Claude's gitignore surface. `.agents/skills/swarm-persona/` (the per-worktree generated bundle) is gitignored by name; the rest of `.agents/skills/` stays committable for curator-promoted knowledge.

### Per-worktree settings branch on backend

`write-worktree-settings!` now takes the agent and branches:
- **claude** — unchanged: `.claude/settings.local.json` with auto-compaction env keys, `UserPromptSubmit`/`Stop` hooks, `permissions.allow`, optional `advisorModel`.
- **pi** — `.pi/settings.json` with `swarmforge.autoCompactPct: 0.88`, `swarmforge.autoCompactWindow: 200000`, `compaction.enabled: true`. No advisor, no hooks, no permissions.

### A bundled `swarmforge-pi` extension restores the two behaviors pi has no JSON config for

`swarmforge/scripts/extensions/swarmforge-pi.ts` ships in-repo (inside `scripts/` so it syncs into worktrees automatically) and is loaded via `--extension`:

1. **agent-running marker** — `pi.on("message_start")` for role `user` touches `<cwd>/.swarmforge/agent-running`; `agent_end` / `session_shutdown` remove it. Restores the Claude `hooks.UserPromptSubmit`/`hooks.Stop` behavior (ADR 0020) for watchdogs/observability.
2. **Percentage auto-compaction** — `pi.on("turn_end")` reads `ctx.getContextUsage()` (`{tokens, contextWindow}`) and calls `ctx.compact()` when `tokens > contextWindow * pct`. pi's native compaction uses a fixed token reserve, not a percentage of the window; this extension tightens the trigger to SwarmForge's 88%-of-200k threshold (mirroring `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=88`). Config precedence: `SWARMFORGE_AUTOCOMPACT_PCT`/`SWARMFORGE_AUTOCOMPACT_WINDOW` env > `.pi/settings.json` `swarmforge.*` > defaults.

The extension follows pi's canonical `trigger-compact.ts` example pattern.

### `agent-retro` supports pi transcripts

`extract.py` auto-detects the format from the first line (`{"type":"session"}` → pi; otherwise Claude) and routes to a pi parser that produces the same schema (`conversation_arc`, `tokens.total`, `tokens.estimated_cost_usd`, `tool_result_sizes`, `tools`). pi's `AssistantMessage.usage` carries `{input, output, cacheRead, cacheWrite, totalTokens, cost:{...}}` — the full token/cost budget, mapped to the existing key names. The skill documents pi's session path encoding (`~/.pi/agent/sessions/<encoded-cwd>/...`, cwd wrapped in `--` with `/ \ :` → `-`), which differs from Claude's double-dash scheme. `${CLAUDE_SKILL_DIR}` is resolved with a pi-compatible fallback.

## Explicitly out of scope

- **Permission model / allowlist.** SwarmForge's Claude safety property ("autonomous, but a whitelist gates `gh pr merge*`/`git reset --hard*`") is **not** replicated for pi. pi has no per-command allowlist and no permission prompts; it is always autonomous. A `tool_call`-intercepting extension could restore it, but this fork declines to build one (decision: ignore). Operators running pi unattended should use pi's documented containerization/micro-VM patterns if they need isolation.
- **`--permission-mode auto` (ADR 0019).** No pi equivalent; unneeded (pi is autonomous by default).
- **`advisorModel` (ADR 0012).** No pi equivalent (Claude in-editor advisor feature). The `advisor=<model>` token is accepted as a no-op for pi so configs stay portable across backends; it is discarded, not written to `.pi/settings.json`.

## Pending implementation

This ADR is implemented in the `feat/pi-backend` branch:
- `swarmforge.bb`: `parse-config` whitelist + `launch-command` `pi` branch + agent threaded into `write-worktree-settings!`.
- `fork.bb`: `write-persona-skill-file!` / `install-skills!` write to `.agents/skills/`; `link-skills!` dir symlink; `write-worktree-settings!` branches on backend.
- `swarmforge/scripts/extensions/swarmforge-pi.ts`: bundled extension.
- `swarmforge/skills/setup-swarm/SKILL.md`: pi-aware steps, `.claude` gitignore removed.
- `swarmforge/skills/agent-retro/`: pi transcript parser + path docs.
- `.gitignore`: `.claude` entries removed.
- `test/fork_runner.bb`: pi coverage.

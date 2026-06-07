# Permanent fork of unclebob/swarm-forge with minimal diff policy

This repo (`gabadi/swarm-forge`) is a permanent fork of `unclebob/swarm-forge`. No changes are contributed back upstream. The policy is **minimal diff**: every divergence must be intentional and documented here. When rebasing against upstream, preserve permanent divergences and drop temporary ones only after verifying upstream has fixed them.

## Current divergences

### Permanent

**cmux multiplexer backend** — `main` branch, commits `863666c` and `655c457`

Files changed: `swarmforge/scripts/swarm-mux.sh` (new), `swarmforge/scripts/swarmforge.sh`, `swarmforge/scripts/swarm-cleanup.sh`, `swarmforge/scripts/swarm-stop.sh`, `README.md`. Deleted: `swarmforge/scripts/terminal-adapters/cmux.sh`.

Upstream only supports tmux. This environment runs inside cmux, where tmux behaves unreliably. The backend adds a pluggable multiplexer abstraction (`swarm-mux.sh`) that auto-detects cmux via `CMUX_*` env vars and runs each role as a native cmux workspace grouped under `SwarmForge · <project>`. When rebasing, always reapply these two commits on top of the updated upstream `main`.

---

**Self-referencing fork URL** — runnable branches (`four-pack`, `six-pack`), commit `ded6019`

The `./swarm` wrapper downloads shared scripts from `gabadi/swarm-forge`, not `unclebob/swarm-forge`. This must always point to this fork so projects get scripts that include the cmux backend. When rebasing runnable branches, reapply this URL change on top.

---

**Prompt bundle inlining (Idea B)** — `main` branch

Files changed: `swarmforge/scripts/swarmforge.sh` — replaced `write_agent_instruction_file` with `resolve_prompt_bundle` (BFS over constitution + referenced files + role prompt, written as a flat bundle to `.swarmforge/prompts/<role>.md`). The bundle is passed via `--append-system-prompt-file` so it arrives in the system prompt and survives `/clear`.

When rebasing, preserve the `resolve_prompt_bundle` function and the updated `write_agent_instruction_file` body. Check whether upstream has added a similar inlining mechanism — if so, assess compatibility before reapplying.

---

**Notify harness — durable handoff delivery (Idea A)** — `main` branch

Files changed: `swarmforge/scripts/swarmforge.sh` (updated `write_notify_script`, added `write_worktree_settings` Stop hook entry), `swarmforge/scripts/swarm-stop-hook.sh` (new). Also: `write_sessions_file` now emits a 6th column (worktree path).

Replaces the honor-system message delivery with a shell harness: commit hash appended to every handoff message, full message stored durably in sender's `logbook.json` (JSON Lines via jq), idle check via receiver's logbook before delivery, and `/clear` + bundle re-inject before each message send. The Stop hook fires when an agent finishes and delivers any queued message to itself.

Requires `jq` (added to `check_dependency` calls). When rebasing, verify `swarm-stop-hook.sh` is preserved, `write_notify_script` retains the logbook + delivery logic, and `write_sessions_file` still emits 6 columns.

---

**Auto-compaction on role worktrees (Idea F)** — `main` branch

Files changed: `swarmforge/scripts/swarmforge.sh` — new `write_worktree_settings` function called in `prepare_worktrees` for each non-master worktree. Merges `autoCompactEnabled: true`, `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=88`, and `CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000` into `.claude/settings.local.json` at each launch.

When rebasing, preserve the `write_worktree_settings` call in `prepare_worktrees`.

---

**swarmforge/ write deny on role worktrees (Idea I)** — `main` branch

Files changed: `swarmforge/scripts/swarmforge.sh` — `write_worktree_settings` also merges a `permissions.deny` block preventing roles from editing `swarmforge/**` and their own `settings.local.json`. Written fresh each launch; roles cannot lift the lock.

When rebasing, preserve the `permissions.deny` block in `write_worktree_settings`.

---

**swarm-cleanup --all mode (Idea H)** — `main` branch

Files changed: `swarmforge/scripts/swarm-cleanup.sh` — additive `--all` branch kills every `swarmforge-*` tmux session and all `SwarmForge`-prefixed cmux workspace groups. Existing positional form is unchanged.

When rebasing, preserve the `--all` branch in `swarm-cleanup.sh`.

---

**Per-technology engineering templates (Idea G)** — `main` branch

Files added: `swarmforge/engineering-templates/engineering-{go,clojure,java}.prompt` (tool commands for each language), `swarmforge/engineering-templates/setup-{go,clojure,java}.prompt` (agent-executable install + `engineering.prompt` generation instructions). The runnable branches (`four-pack`, `six-pack`) carry no `engineering.prompt` — it is generated per project at install time from the setup prompt for the chosen language.

When rebasing, preserve the `engineering-templates/` directory. Check whether upstream has added language templates; if so, assess whether to merge or keep separate.

### Temporary (drop once upstream fixes)

**logbook.json contradiction** — `four-pack` commit `6770ae4`, `six-pack` commit `d8b2e27`

File changed: `swarmforge/constitution/workflow.prompt` on each branch. Upstream's `workflow.prompt` told agents to commit `logbook.json`, but the file is gitignored — a direct contradiction. Fix: changed "tracked" to "local untracked" and removed the commit instruction. When rebasing, first check whether upstream has resolved this contradiction. If upstream has fixed it, drop these commits. If not, reapply them on both runnable branches.

## Proposed divergences

Ideas under consideration. Not yet designed or implemented. Each has a detailed spec in `docs/ideas/`. When each is decided: move it to **Current divergences** with files, classification, and rebase instruction — or strike it as rejected.

| Idea | Summary | Spec | Open questions |
|------|---------|------|----------------|
| C | Integrator role — owns PR + CI + merge; specifier moves to own worktree | [idea-C](../ideas/idea-C-integrator-role.md) | None |
| D | Role idle gates — no handoff = no action, remove startup install directives | [idea-D](../ideas/idea-D-idle-gates.md) | None |
| E | Back-routing defects — route to directly-upstream role with failing step + repro | [idea-E](../ideas/idea-E-back-routing-defects.md) | None |
| J | Session retro — `entire` auto-collects traces, `agent-retro` runs per turn | [idea-J](../ideas/idea-J-session-retro-entire.md) | None |
| K | Setup / preflight — `entire enable` + `entire agent add` per backend, automatic at first `./swarm` | [idea-K](../ideas/idea-K-setup-preflight.md) | None |
| L | Gherkin header sections — 7 mandatory sections per feature file (rubric + format) | [idea-L](../ideas/idea-L-gherkin-header-sections.md) | None |
| M | UX Intent in the pipeline — specifier authors UX Intent, coder reads it, UX Reviewer role (six-pack only) | [idea-M](../ideas/idea-M-ux-intent-pipeline.md) | None |

**Rejected**: D12–D15 (engineering prompt tweaks — test-type separation, property-test close-out, full-mutation rule, Gherkin mutation command inline) — too much prompt drift from upstream. D24 (role prompt restructure into Standing rules + numbered Lifecycle) — same reason.

## Rebase procedure for agents

1. Add upstream as a remote: `git remote add upstream https://github.com/unclebob/swarm-forge.git`
2. Fetch: `git fetch upstream --all`
3. For each branch (`main`, `four-pack`, `six-pack`): rebase onto the upstream branch
4. After rebase, verify permanent divergences survived (check `swarm-mux.sh` exists, fork URL is correct)
5. For temporary divergences: check if upstream now ships the fix. If yes, do not reapply. If no, cherry-pick the fix commit onto both runnable branches.
6. Remove temp remote: `git remote remove upstream`

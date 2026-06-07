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

### Temporary (drop once upstream fixes)

**logbook.json contradiction** — `four-pack` commit `6770ae4`, `six-pack` commit `d8b2e27`

File changed: `swarmforge/constitution/workflow.prompt` on each branch. Upstream's `workflow.prompt` told agents to commit `logbook.json`, but the file is gitignored — a direct contradiction. Fix: changed "tracked" to "local untracked" and removed the commit instruction. When rebasing, first check whether upstream has resolved this contradiction. If upstream has fixed it, drop these commits. If not, reapply them on both runnable branches.

## Proposed divergences

Ideas under consideration. Not yet designed or implemented. Each has a detailed spec in `docs/ideas/`. When each is decided: move it to **Current divergences** with files, classification, and rebase instruction — or strike it as rejected.

| Idea | Summary | Spec | Open questions |
|------|---------|------|----------------|
| A | Notify harness — shell queue, `/clear` + bundle re-inject, Stop hook idle signal, commit hash in trailer | [idea-A](../ideas/idea-A-notify-harness.md) | Job-complete discriminator for Stop hook |
| B | Prompt bundle inlining at launch — flat concat, system prompt delivery | [idea-B](../ideas/idea-B-prompt-bundle-inlining.md) | None |
| C | Integrator role — owns PR + CI + merge | [idea-C](../ideas/idea-C-integrator-role.md) | Do target projects have CI? |
| D | Role idle gates — no handoff = no action, remove startup install directives | [idea-D](../ideas/idea-D-idle-gates.md) | None |
| E | Back-routing defects — route to directly-upstream role with failing step + repro | [idea-E](../ideas/idea-E-back-routing-defects.md) | None |
| F | Auto-compaction on role worktrees — 88%/200k | [idea-F](../ideas/idea-F-auto-compaction.md) | None |
| G | Per-technology engineering file — selected at install time | [idea-G](../ideas/idea-G-per-tech-engineering-file.md) | How does install-time selection work? |
| H | swarm-cleanup --all mode | [idea-H](../ideas/idea-H-cleanup-all-mode.md) | None |
| I | swarmforge/ write deny on role worktrees | [idea-I](../ideas/idea-I-swarmforge-write-deny.md) | None |
| J | Session retro via `entire dispatch --local` + `retro-triage` | [idea-J](../ideas/idea-J-session-retro-entire.md) | Depends on K |
| K | Setup / preflight — `entire enable`, tool check, engineering template | [idea-K](../ideas/idea-K-setup-preflight.md) | Skill vs automatic preflight? |
| L | Gherkin header sections — ~3 mandatory sections per feature file | [idea-L](../ideas/idea-L-gherkin-header-sections.md) | Which 3 sections? |
| M | UX Intent in the pipeline — specifier authors UX Intent, coder reads it, UX Reviewer role | [idea-M](../ideas/idea-M-ux-intent-pipeline.md) | None |

**Rejected**: D12–D15 (engineering prompt tweaks — test-type separation, property-test close-out, full-mutation rule, Gherkin mutation command inline) — too much prompt drift from upstream. D24 (role prompt restructure into Standing rules + numbered Lifecycle) — same reason.

## Rebase procedure for agents

1. Add upstream as a remote: `git remote add upstream https://github.com/unclebob/swarm-forge.git`
2. Fetch: `git fetch upstream --all`
3. For each branch (`main`, `four-pack`, `six-pack`): rebase onto the upstream branch
4. After rebase, verify permanent divergences survived (check `swarm-mux.sh` exists, fork URL is correct)
5. For temporary divergences: check if upstream now ships the fix. If yes, do not reapply. If no, cherry-pick the fix commit onto both runnable branches.
6. Remove temp remote: `git remote remove upstream`

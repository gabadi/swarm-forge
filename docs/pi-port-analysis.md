# SwarmForge → pi Agent Port: Deep Capability Analysis

**Goal:** Produce a SwarmForge backend for the `pi` agent (`@earendil-works/pi-coding-agent`) with the **same capabilities** the fork currently gives Claude Code (`claude` backend). This doc inventories every Claude Code coupling point, explains what each does, and maps it to its pi equivalent (or flags the gap).

---

## 1. SwarmForge architecture (agent-agnostic core — already portable)

The bulk of SwarmForge is agent-agnostic. This layer needs **no changes** for a pi port; only the per-backend launch + per-backend settings/skills wiring changes.

### 1.1 Config-driven topology
- `swarmforge/swarmforge.conf` — one `window <role> <agent> <worktree> [task|batch] [extra-cli-args...]` line per role.
- `swarmforge.bb :: parse-config` validates the file, accepts agent ∈ `{claude, codex, copilot, grok}`, splits out the `advisor=` token (claude-only), and normalizes receive mode `task|batch`.
- **Port impact:** add `pi` to the accepted agent set (`parse-config` whitelist, line ~183).

### 1.2 Worktrees + sparse checkout (ADR 0006)
- One git worktree per role under `.worktrees/<role>` (or `master`/`none`).
- `fork.bb :: sparse-checkout-setup!` hides the QA holdout path from non-specifier/QA roles.
- **Port impact:** none. Worktree mechanics are independent of the agent backend.

### 1.3 Session layer (tmux or herdr)
- Project-isolated tmux socket in `/tmp/swarmforge-<uid>/<crc>.sock`; honors `base-index`/`pane-base-index`.
- `herdr` is now a native session layer (recently merged) as an alternative to tmux.
- Terminal surface adapters: `terminal-app`, `iterm2`, `ghostty`, `windows-terminal`, `none`, `herdr`.
- Window watchdog reopens crashed/closed non-cleanup windows.
- **Port impact:** none. The session layer runs the agent's launch command in a pane/tab; it is backend-agnostic.

### 1.4 Handoff protocol + daemon (agent-agnostic file transport)
- `handoffd.bb` owns tmux socket access, watches each role's `.swarmforge/handoffs/outbox/`, validates, copies to recipient inboxes, sends generic wake-ups.
- Helper scripts (synced into each worktree's `swarmforge/scripts/`, on `PATH`):
  - `swarm_handoff.sh` — validate + queue outbound drafts (`awake` / `git_handoff` / `note`).
  - `ready_for_next.sh` → `ready_for_next_task.sh` / `ready_for_next_batch.sh` — accept work.
  - `done_with_current.sh` → `done_with_current_task.sh` / `done_with_current_batch.sh` — complete work.
- Receive mode (`task`/`batch`) is written to `.swarmforge/roles.tsv` and read by the helpers at runtime.
- **Port impact:** none. Agents invoke shell scripts; the protocol is agent-agnostic. The wake-up is a tmux/herdr message, not an agent API call.

### 1.5 Constitution + role prompts
- `swarmforge/constitution.prompt` → `swarmforge/constitution/articles/*.prompt` (shared: `engineering`, `handoffs`, `workflow`; local overrides: `project`, `local-engineering`, `local-workflow`).
- `swarmforge/roles/<role>.prompt` per role.
- Shared articles are installed from `main` into runnable branches/worktrees, skipping existing local files (override semantics).
- **Port impact:** none for the article content; only the *delivery* mechanism changes (see §2.2).

### 1.6 Quality tooling + setup
- `setup-swarm` skill (one-time): asks stack, installs language mutation/CRAP/DRY tools + APS `gherkin-parser`/`gherkin-mutator`, wires `entire` session tracking, writes permission allow-rules, scaffolds `.gitignore`, probes default branch, emits `.swarmforge/setup-complete` marker.
- `engineering.prompt` language tool table (Go/Clojure/Java) + APS doctrine.
- **Port impact:** the **permission allow-rules step** (§2.5) and the **session-tracking step** (§2.6) are Claude-specific; the rest is portable.

---

## 2. The Claude Code coupling surface (the part a pi port must replicate)

This is the complete inventory of places where SwarmForge touches Claude Code specifically. Each is mapped to its pi equivalent below.

### 2.1 Launch command — `swarmforge.bb :: launch-command` (lines ~360–374)

For `claude`, the constructed command is:

```sh
export SWARMFORGE_ROLE='<role>' && export PATH='<worktree>/swarmforge/scripts':$PATH && cd '<worktree>' \
  && claude --append-system-prompt-file '<prompt-file>' --permission-mode auto -n 'SwarmForge <Display>' <extra-args>
```

Key Claude-specific behaviors:
- `--append-system-prompt-file <file>` — injects the role bundle as an *appended* system prompt.
- `--permission-mode auto` — never blocks on a permission prompt (unattended autonomous mode, ADR 0019). Skipped if `--permission-mode` already present in extra-args.
- `-n 'SwarmForge <Display>'` — sets the session/conversation display name.
- `<extra-args>` passthrough — e.g. `--model claude-opus-4-8 --effort high`.
- First window (index 0) appends a cleanup hook that runs `swarm-cleanup.sh` on exit.

**pi equivalent (verified by running `pi --help` + reading `dist/core/resource-loader.js :: resolvePromptInput`):**
- `pi --append-system-prompt <arg>` — pi resolves `<arg>` as a **file path first** (`existsSync(input)` → `readFileSync`); only if the path does *not* exist is the arg treated as literal text. So `pi --append-system-prompt /path/to/pointer.md` is the exact analogue of `claude --append-system-prompt-file`. ✓ (Note: pi's flag is `--append-system-prompt`, **not** `--append-system-prompt-file`.)
- Session name: `--name 'SwarmForge <Display>'` / `-n`. ✓
- Model/thinking: `--provider`, `--model <pattern>` (supports `provider/id` and `:<thinking>` shorthand e.g. `sonnet:high`), `--thinking <level>`. ✓ (different syntax than `--effort`).
- **Permission mode: NO direct equivalent.** See §2.5 / §4.2.

### 2.2 Inlined prompt bundle + swarm-persona skill — ADR 0017 (`fork.bb :: write-persona-skill-file!`, `resolve-prompt-bundle`)

- At launch, SwarmForge *pre-resolves* the constitution + role prompt transitively (following `swarmforge/.../*.prompt` references + all `constitution/articles/*.prompt`), dedups, and bundles them into a single `.claude/skills/swarm-persona/SKILL.md` inside the worktree.
- The skill body is an XML envelope `<swarmforge_agent_context role="…">` with one `<file path="…">` block per resolved prompt file, plus `AGENTS.md` and `.agents/roles/<role>.md` (ADR 0014 knowledge injection) when present.
- `write-agent-instruction-file!` is overridden (in `fork.bb`) to write a short pointer: *"Your full role, constitution, and operating instructions are in your swarm-persona skill."* — this short pointer is what `--append-system-prompt-file` injects, so the agent loads the bundled skill rather than re-reading the raw `.prompt` files.

**Why this design:** clear-first delivery (ADR 0002) wipes the session; the bundle is the re-injectable unit. The XML `<file>` boundaries let the agent distinguish constitution from role prompt from knowledge files, and dedup prevents articles appearing 2–3×.

**Current SwarmForge skill-install behavior (clarification):** skills are installed **directly into `.claude/skills/`**, *not* `.agents/skills/`. `install-skills!` writes local skills (`agent-retro`, `setup-swarm`) + pinned `entire`/`mattpocock` tarballs into `<project>/.claude/skills/`. Separately, `link-curator-skills!` symlinks `<worktree>/.agents/skills/*` → `<worktree>/.claude/skills/` so the curator's promoted skills (ADR 0013) become visible to Claude. So today: `.agents/skills/` is the *curator's output dir* (canonical, per six-pack `curator.prompt` line 29: `.agents/skills/<name>/` is where the curator writes procedures), and `.claude/skills/` is the *effective skill dir* Claude reads.

**pi equivalent:** pi skills live in `.pi/skills/`, `~/.pi/agent/skills/`, `.agents/skills/` (discovered from cwd + ancestors after project trust), or via `--skill <path>`. The Agent Skills spec format (frontmatter `name`/`description` + body) is identical to Claude Code skills. ✓
- pi also loads `AGENTS.md`/`CLAUDE.md` context files automatically from cwd + parents + `~/.pi/agent/AGENTS.md`. So `AGENTS.md` is *already* auto-injected by pi — duplicating it into the skill would double-load it.
- pi has `.pi/SYSTEM.md` (replace system prompt) and `.pi/APPEND_SYSTEM.md` (append) as project files — a clean place to put the role-bundle pointer without a skill, **but** the bundle approach (one inlined artifact per role) is still valuable for dedup + clear-first re-injection.
- **Port plan (skills dir decision — unified, applies to BOTH claude and pi backends):** make `.agents/skills/` the **single real directory** for all skills, and expose it to Claude via **one directory-level symlink**, not per-skill links. Specifically:
  1. **`install-skills!` writes into `.agents/skills/`** only (local SwarmForge skills `agent-retro` + `setup-swarm`, plus pinned `entire`/`mattpocock` tarballs). This is a change for the claude backend too — today it writes to `.claude/skills/`.
  2. **`write-persona-skill-file!` writes into `.agents/skills/swarm-persona/SKILL.md`** (not `.claude/skills/...`).
  3. **Generalize `link-curator-skills!` → `link-skills!`**: create **one symlink** `.claude/skills` → `../.agents/skills` (the whole directory). Replace the existing per-skill loop. If `.claude/skills` already exists as a real directory (old layout), remove it first (`rm -rf .claude/skills`) then `ln -sfn ../.agents/skills .claude/skills`. Do **not** `create-dirs .claude/skills` — it must be a symlink, not a dir. (`.claude/` itself stays a real dir because `write-worktree-settings!` writes `.claude/settings.local.json` and `setup-swarm` writes `.claude/settings.json` there.)
  4. **pi needs no symlink** — pi auto-discovers `.agents/skills/` from cwd + ancestors after `--approve`. The symlink is harmless for pi (it ignores `.claude/`), so one code path serves both backends.
  5. **`.gitignore`: remove every `.claude` entry completely.** Today the repo `.gitignore` carries `.claude/*` + `!.claude/skills/`, and `setup-swarm` Step 5 appends `.claude/skills/swarm-persona/`. All three go away — no `.claude*` lines in `.gitignore` at all. Swarm no longer manages Claude's gitignore surface.
     - Consequence: `.claude/skills` (a symlink) and `.claude/settings.local.json` (per-worktree generated) become visible to git in the `master` checkout. The symlink committing is fine (stable across clones); `.claude/settings.local.json` showing as untracked is acceptable (role worktrees live under gitignored `.worktrees/`, so only the `master` role's file is visible). If the operator wants it ignored, that's now their repo's decision, not swarm's.
     - **One open detail for `.agents/skills/` gitignore:** the dir now holds *both* generated skills (launcher-installed `agent-retro`/`setup-swarm`/`entire`/`mattpocock` + per-worktree `swarm-persona`) *and* the curator's committed promoted skills (ADR 0013 — versioned project knowledge). We cannot gitignore the whole `.agents/skills/` or we'd hide curator knowledge. Resolution (to confirm at implementation time): gitignore only the *generated* skill dirs by name (`.agents/skills/swarm-persona/`, and the pinned/installed set) OR rely on the curator committing only what it promotes and letting installed skills show as untracked. Lean toward the named-ignore approach so `git status` stays clean without hiding curator output.
  This unifies the curator contract (six-pack `curator.prompt` already treats `.agents/skills/<name>/` as canonical) with the launcher's install, and gives pi the auto-discovery it expects with a single dir-level symlink for Claude.
- **Bundle plan:** generate `.agents/skills/swarm-persona/SKILL.md` per worktree with the same XML-envelope bundle (it lands in the same real dir as everything else, and is symlinked to `.claude/skills/` for claude, auto-discovered by pi). Inject the pointer via `pi --append-system-prompt <pointer-file>`. Skip `AGENTS.md` from the bundle body (pi loads it natively via `loadContextFileFromDir`) but *keep* `.agents/roles/<role>.md` in the bundle (role-specific, not auto-loaded).

### 2.3 Per-worktree settings + auto-compaction — ADR 0020 (`fork.bb :: write-worktree-settings!`)

Writes `<worktree>/.claude/settings.local.json` with:
- `autoCompactEnabled: true`
- `env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE: "88"`
- `env.CLAUDE_CODE_AUTO_COMPACT_WINDOW: "200000"`
- `hooks.UserPromptSubmit` → `touch .swarmforge/agent-running`
- `hooks.Stop` → `rm -f .swarmforge/agent-running`
- `permissions.allow` merged with `["Bash(gh pr merge*)", "Bash(git reset --hard origin/*)"]`
- `advisorModel: <model>` when `advisor=<model>` token present (ADR 0012).

**pi equivalent:**
- Auto-compaction: pi has `compaction.enabled`, `compaction.reserveTokens`, `compaction.keepRecentTokens` in `.pi/settings.json` (project) or `~/.pi/agent/settings.json` (global). There is **no percentage-override** env var equivalent; pi triggers when `contextTokens > contextWindow - reserveTokens`. The closest port: set `compaction.enabled: true` and tune `reserveTokens`/`keepRecentTokens`. ⚠️ partial.
- `advisorModel`: **no pi equivalent** (Claude Code in-editor advisor feature). ⚠️ drop or no-op for pi.
- `hooks.UserPromptSubmit` / `hooks.Stop`: pi has **no JSON-config shell hooks** like Claude Code's `settings.json` hooks. The equivalent is a **pi extension** (TypeScript module subscribing to lifecycle events: `session_start`, `message`/`user_message`, `agent_stop`/`session_end`). ⚠️ requires a small extension, or skip the `agent-running` marker if not needed (it's used for watchdog/observability).
- `permissions.allow` rules: **no direct pi equivalent** — pi has no per-Bash-command allowlist gating (see §2.5). ⚠️

### 2.4 Permission allow-rules — `setup-swarm` Step 4 + `fork.bb`

- `setup-swarm` writes `.claude/settings.json` with `permissions.allow: ["Bash(gh pr merge*)", "Bash(git reset --hard*)"]` so the integrator/specifier run git/gh unattended.
- `fork.bb :: write-worktree-settings!` additionally adds `Bash(gh pr merge*)` and `Bash(git reset --hard origin/*)` to each worktree's `.claude/settings.local.json`.
- Combined with `--permission-mode auto` (ADR 0019), this lets roles run shell commands without prompting while still being able to do PR merges / hard resets.

**pi equivalent:** ⚠️ **This is the biggest gap.** Pi has **no built-in permission-prompt system** and no per-command allowlist. Pi's security model (per `docs/security.md`):
- Pi runs with the user's permissions; built-in tools can read/write/run anything the user can.
- There is no interactive "approve this bash command" gate like Claude Code's. There is no `--permission-mode`.
- The only input-loading guard is **project trust** (`--approve` / `defaultProjectTrust`) — whether to *load* project resources, not whether to *run* a command.
- A pi **extension** can intercept `tool_call` events (e.g. block/allow `bash` commands matching patterns) — this is the closest mechanism to an allowlist, but it's an extension you write, not a JSON config.

**Implication for the port:** SwarmForge's "autonomous but with a load-bearing whitelist" posture (ADR 0019) does not translate directly. Options:
1. **Accept pi's model:** pi is *always* autonomous by default (no prompts to suppress). The allowlist is then unnecessary *for unattended operation* — but it loses the safety property that only `gh pr merge*` / `git reset --hard*` are privileged. In pi, every bash command already runs unattended.
2. **Write a `swarmforge-permissions` extension** that subscribes to `tool_call` and blocks commands outside an allowed set (replicating the Claude allowlist as a hard gate). This restores the safety property but is new code.
3. **Run pi inside a container/Gondolin micro-VM** (pi's documented pattern for untrusted/unmonitored work) — coarse-grained filesystem/network isolation instead of a command allowlist.

This is a design decision the port must make explicitly (likely a new ADR).

### 2.5 Session tracking + transcript extraction — `agent-retro` skill + `setup-swarm` Step 3

- `setup-swarm` runs `entire enable` and `entire agent add <backend>` for each backend.
- `agent-retro` (auto-run before each role goes idle, per `handoffs.prompt`) extracts the session transcript:
  - **Primary:** `entire session current --json` → check `worktree_path == $PWD` → `entire session info <id> --transcript > /tmp/retro-session.jsonl` → `extract.py --metadata-only` verify → `extract.py --summary > /tmp/retro-extract.json`.
  - **Fallback (Claude Code only):** `~/.claude/projects/<encoded-cwd>/*.jsonl` (most recent). Note the `.worktrees` → `--worktrees` double-dash encoding quirk.
- `retro-triage` (operator skill, `.claude/skills/`) batches retros into root-cause diagnoses.

**pi equivalent:**
- pi stores sessions as JSONL under `~/.pi/agent/sessions/<encoded-path>/session.jsonl` (per `docs/sessions.md` / `docs/session-format.md`). This is the **native transcript source** — equivalent to Claude Code's `~/.claude/projects/` fallback.
- pi exposes `--session <path|id>`, `--session-id <id>`, `--session-dir <dir>`, `--no-session`, `--export <file>` (HTML). `pi -r` resumes.
- The `entire` CLI is agent-agnostic and already supports `codex`/`copilot`/`grok`; it can likely `entire agent add pi` if `entire` supports it — needs verification. If not, the **JSONL fallback path** is the portable one and pi has a clean equivalent.
- **Port plan:** rewrite `agent-retro` Step 1 fallback to read `~/.pi/agent/sessions/<encoded-cwd>/*.jsonl` (pi's encoding scheme — verify the path encoding, likely similar `-`-escaping of path separators). Keep `entire` as primary if it supports pi. `extract.py` parses a JSONL transcript format; pi's JSONL schema differs from Claude Code's, so `extract.py` needs a **pi parser branch** (or a pi-specific extractor). ⚠️ medium effort.
- `agent-retro` auto-invocation: the trigger is *prose in `handoffs.prompt`* ("run `agent-retro` before idle"), not a harness hook. That works for pi too (it's just an instruction the model follows), **provided** the `agent-retro` skill is loadable by pi (drop it into `.pi/skills/` or `swarmforge/skills/` + sync). ✓

### 2.6 Skill installation + pins — ADR 0018 (`fork.bb :: install-skills!`, `ensure-skills-installed!`, `link-curator-skills!`)

- At launch, installs skills into the project's `.claude/skills/`:
  - Local skills from `swarmforge/skills/` (`agent-retro`, `setup-swarm`).
  - Pinned `entireio/skills` tarball at `ENTIRE_SKILLS_SHA`.
  - Selective `mattpocock/skills` at `MATTPOCOCK_SKILLS_SHA` (only `MATTPOCOCK_SKILLS_INCLUDE`).
- Idempotent: skips if sentinel SHA matches.
- `link-curator-skills!` symlinks `.agents/skills/*` → `.claude/skills/` (ADR 0013/0021 curator knowledge).

**pi equivalent:**
- pi skill locations: `~/.pi/agent/skills/`, `~/.agents/skills/`, project `.pi/skills/`, `.agents/skills/`, packages, settings `skills` array, `--skill <path>`. ✅ **richer than Claude Code's** — pi natively reads `.agents/skills/` and `~/.agents/skills/`, so `link-curator-skills!` is **partially redundant** for pi (`.agents/skills/` is auto-discovered).
- pi can load Claude/Codex skills directly via settings: `"skills": ["../.claude/skills"]`. So the *same installed skills* could be shared, or pi can have its own `.pi/skills/` mirror.
- **Port plan:** add a pi target dir to `install-skills!` (`.pi/skills/`) alongside `.claude/skills/`, or write to `.pi/skills/` only for pi-only worktrees, or rely on pi's `"skills"` setting to point at the existing `.claude/skills/`. The `entire`/`mattpocock` pins are skill *content* (Agent Skills standard), so they're harness-agnostic — same tarballs work for pi. ✓ The main work is just choosing the destination directory and settings wiring.

### 2.7 Curator knowledge injection — ADR 0013/0014

- `.agents/roles/<role>.md` (role knowledge) + root `AGENTS.md` (project knowledge) are injected into the swarm-persona bundle by `write-persona-skill-file!`.
- `.agents/ledger.md` is the append-only audit the curator writes.
- `AGENTS.md` is loaded natively by pi from cwd/parents (no injection needed). `.agents/roles/<role>.md` is **not** auto-loaded by pi → must stay in the bundle (§2.2). ✓

### 2.8 `.claude/settings.local.json` + project trust

- `.claude/settings.local.json` is fork-owned, not upstream-tracked (ADR 0020 rationale). SwarmForge writes it per worktree.
- pi's equivalent is `.pi/settings.json` (project) — also fork-owned, merged over `~/.pi/agent/settings.json`.
- **BUT:** `.pi/settings.json` requires **project trust** on interactive startup. SwarmForge roles run unattended (launched in tmux/herdr panes) — they're non-interactive, and pi's non-interactive modes (`-p`, `--mode json`, `--mode rpc`) **do not show a trust prompt** but also "without an applicable saved decision …" load nothing. So the port must either (a) pre-save a trust decision, (b) pass `--approve` at launch, or (c) avoid `.pi/settings.json` and drive everything via CLI flags + `--skill`/`--append-system-prompt`. ⚠️ launch-time decision.

### 2.9 `agent-running` marker + observability

- The `hooks.UserPromptSubmit`/`hooks.Stop` pair touches/removes `.swarmforge/agent-running` so external watchers know a role is mid-turn vs idle.
- Used by watchdogs/observability; not load-bearing for the handoff protocol itself.
- **pi equivalent:** a pi extension subscribing to `tool_call`/`message`/`session_end` events can replicate this. Or drop it if no pi-side observability consumer exists yet. ⚠️ optional.

---

## 3. Capability inventory — one-line matrix

| # | Claude Code capability | Where it lives | pi equivalent | Status |
|---|---|---|---|---|
| 1 | Append role bundle as system prompt | `launch-command` + `write-agent-instruction-file!` | `--append-system-prompt` (file or text) | ✅ direct |
| 2 | Pre-resolved inlined prompt bundle (XML envelope) | `fork.bb :: write-persona-skill-file!` (ADR 0017) | `.pi/skills/swarm-persona/SKILL.md` + `--skill` / auto-discovery | ✅ port the generator |
| 3 | Autonomous unattended mode (no prompts) | `--permission-mode auto` (ADR 0019) | pi is autonomous by default — no flag needed | ✅/⚠️ see #7 |
| 4 | Per-command allowlist (privileged cmds only) | `.claude/settings.json` `permissions.allow` | **none native** — needs a pi extension or accept pi's open model | ⚠️ **gap / ADR** |
| 5 | Session/conversation display name | `claude -n` | `pi --name` / `-n` | ✅ direct |
| 6 | Per-role model + effort override | extra-args `--model X --effort high` | `--provider`, `--model provider/id:thinking`, `--thinking` | ✅ syntax diff |
| 7 | Per-role advisor model | `advisor=<model>` → `.claude/settings.local.json advisorModel` (ADR 0012) | **none** (Claude in-editor feature) | ⚠️ drop / no-op |
| 8 | Auto-compaction settings | `.claude/settings.local.json` env keys (ADR 0020) | `.pi/settings.json` `compaction.{enabled,reserveTokens,keepRecentTokens}` | ⚠️ partial (no % override) |
| 9 | UserPromptSubmit / Stop hooks → agent-running marker | `.claude/settings.local.json` hooks | pi extension lifecycle events | ⚠️ needs extension or skip |
| 10 | Skill install (local + pinned entire/mattpocock) | `fork.bb :: install-skills!` (ADR 0018) | `.pi/skills/` + `skills` setting; `.agents/skills/` auto-discovered | ✅ port target dir |
| 11 | Curator skill symlinks | `link-curator-skills!` | pi auto-discovers `.agents/skills/` natively | ✅ mostly redundant |
| 12 | Knowledge injection (AGENTS.md + role .md) | bundle body (ADR 0014) | AGENTS.md auto-loaded; `.agents/roles/<role>.md` stays in bundle | ✅ port (skip AGENTS.md) |
| 13 | Transcript extraction for retros | `agent-retro` + `extract.py` (`entire` / `~/.claude/projects`) | `~/.pi/agent/sessions/<path>/*.jsonl` + pi parser branch | ⚠️ medium effort |
| 14 | Auto-run retro before idle | prose in `handoffs.prompt` + `agent-retro` skill | same prose + skill in `.pi/skills/` | ✅ works as-is |
| 15 | Operator retro-triage skill | `.claude/skills/retro-triage` | `.pi/skills/retro-triage` (or shared via `skills` setting) | ✅ portable |
| 16 | Fork upstream sync skill | `.claude/skills/fork-upstream-sync` | `.pi/skills/` (content is agent-agnostic) | ✅ portable |
| 17 | Session layer (tmux/herdr) + handoff daemon | `swarmforge.bb` + `handoffd.bb` + helpers | unchanged | ✅ none |
| 18 | Worktrees + sparse checkout | `swarmforge.bb` + `fork.bb` | unchanged | ✅ none |
| 19 | Constitution + role prompts | `swarmforge/constitution*`, `swarmforge/roles/*` | unchanged (delivery via bundle) | ✅ none |
| 20 | Setup marker / one-time setup | `setup-swarm` skill | portable; swap §2.4 permission step + §2.5 session step | ⚠️ partial rewrite |

---

## 4. Gaps — decisions (post-review)

| # | Gap | Decision | Action |
|---|---|---|---|
| 1 | Permission model / allowlist | **IGNORE** | Drop the Claude `permissions.allow` step for pi; accept pi's autonomous model. No `swarmforge-permissions` extension. |
| 2 | `--permission-mode auto` | **IGNORE** | No flag needed; pi is autonomous by default. |
| 3 | Project trust at unattended launch | **APPROVE** | Pass `--approve` in the pi launch command so `.pi/` + `.agents/` resources load without a trust prompt. |
| 4 | Auto-compaction parity | **RESEARCH + IMPLEMENT as extension** | See §4.4 — pi has no `%`-of-window trigger; replicate SwarmForge's 88%-of-window behavior via a `swarmforge` pi extension that triggers compaction on a percentage threshold. |
| 5 | `advisorModel` | **DISCARD** | Drop `advisor=` for pi (accept token as no-op in `parse-config` so configs stay portable). |
| 6 | `agent-running` marker + autocompaction hooks | **IMPLEMENT as a `swarmforge` pi extension, bundled in-repo and loaded at startup** | One extension in `swarmforge/extensions/swarmforge-pi/` shipped with SwarmForge, loaded via `--extension` in the launch command. See §4.6. |
| 7 | Transcript format for `agent-retro` | **INVESTIGATE + IMPLEMENT** | Add a pi JSONL parser branch to `extract.py`. See §4.7 — format is fully documented. |

### 4.4 Auto-compaction — research findings (pi source: `dist/core/compaction/compaction.js`)

pi's native compaction trigger (`shouldCompact`, line 152):
```js
if (!settings.enabled) return false;
return contextTokens > contextWindow - settings.reserveTokens;  // reserveTokens default 16384
```
This is a **fixed token reserve**, not a percentage of the context window. SwarmForge's Claude setting is `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=88` (compact at 88% of window) + `CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000`. There is **no pi setting** that produces percentage-of-window behavior — `reserveTokens` is absolute, and `keepRecentTokens` (default 20000) only governs *how much* is kept, not *when* it fires.

**Implementation plan — `swarmforge` pi extension (autocompaction):** *Verified against `docs/extensions.md` + `dist/core/extensions/types.d.ts`.*
- The extension API exposes **`ctx.getContextUsage()`** → `{ tokens: number|null, contextWindow: number }` (per `types.d.ts` lines 194–195). This is the exact input the trigger needs.
- The extension API exposes **`ctx.compact({ customInstructions, onComplete, onError })`** to trigger compaction programmatically (no need to emit internal events).
- Hook a check on `message_end` (fires for every finalized message) and/or `before_agent_start`: read `ctx.getContextUsage()`, and when `tokens > contextWindow * pct`, call `ctx.compact()`. `before_agent_start` is the cleanest cut point (pre-flight, before the model call).
- Read `pct` + `window` from `.pi/settings.json` under `swarmforge.autoCompactPct` (default 0.88) / `swarmforge.autoCompactWindow` (default 200000), so the swarm pins its own behavior regardless of pi's `reserveTokens`. If `contextWindow` reported by pi differs from the configured window, use the configured window as the denominator (mirrors Claude's fixed `CLAUDE_CODE_AUTO_COMPACT_WINDOW`).
- Keep pi's native `compaction.enabled: true` as the floor; the extension tightens the trigger to the percentage SwarmForge wants.

This restores ADR 0020's intent (compact at 88% of a 200k window, in the role's terms) without waiting for pi to grow a percentage setting.

### 4.6 `agent-running` marker + autocompaction — one bundled extension

**Shape:** a single TypeScript extension `swarmforge/extensions/swarmforge-pi/` shipped in this repo, loaded by every pi role via `--extension <repo>/swarmforge/extensions/swarmforge-pi` in `launch-command`. It owns the SwarmForge-specific behaviors pi has no native config for. *Event names verified against `docs/extensions.md`:*

1. **`agent-running` marker** — `pi.on("message_start", ...)` fires for every user/assistant/toolResult message; treat a `user` message as the turn-start signal → `touch <worktree>/.swarmforge/agent-running`. `pi.on("session_shutdown", ...)` + `pi.on("agent_end", ...)` → `rm -f` the marker when the agent goes idle/stops. Restores the Claude `hooks.UserPromptSubmit`/`hooks.Stop` behavior (ADR 0020) for watchdogs/observability. (`message_start` for role `user` is the precise analogue of Claude's `UserPromptSubmit`.)
2. **Percentage autocompaction** — §4.4 above (`before_agent_start` + `ctx.getContextUsage()` + `ctx.compact()`).

**Bundling/install:** the extension is part of SwarmForge itself (not an external npm package). `launch-command` references it by absolute path in the worktree, so no `pi install` is needed. `setup-swarm` gains a pi step that writes `.pi/settings.json` with `swarmforge.autoCompactPct: 0.88` + `swarmforge.autoCompactWindow: 200000` and the extension path. This keeps SwarmForge self-contained and versioned with the swarm.

### 4.7 Transcript extraction — investigation results (pi source: `docs/session-format.md` + `dist/core/session-manager.js`)

**pi session location:** `~/.pi/agent/sessions/<encoded-cwd>/<timestamp>_<uuid>.jsonl`, where the encoding is (`getDefaultSessionDirPath`, line 221):
```js
`--${resolvedCwd.replace(/^[/\\]/, "").replace(/[/\\:]/g, "-")}--`
```
i.e. leading `/` stripped, then every `/` `\` `:` → `-`, wrapped in `--...--`. Example on disk: `--Users-gabadi-.agents-skills--`. **This differs from Claude Code's `.worktrees` → `--worktrees` double-dash scheme** — pi collapses each path separator to a single `-`, so `.worktrees/coder` → `-worktrees-coder` inside the wrapper. The `agent-retro` finder must use pi's exact encoding, not Claude's.

**JSONL record schema (v3, fully documented):**
- Line 1 = `SessionHeader`: `{"type":"session","version":3,"id":<uuid>,"timestamp":<ISO>,"cwd":<path>}`.
- Subsequent lines = `SessionEntryBase` + payload: `{"type":"message"|"model_change"|"thinking_level_change"|"compaction"|"branch_summary"|"custom"|"custom_message","id":<8-hex>,"parentId":<id|null>,"timestamp":<ISO>,...}`.
- `type:"message"` entries carry an `AgentMessage` in `message` with `role` ∈ `user | assistant | toolResult | bashExecution | custom | branchSummary | compactionSummary`.
- `AssistantMessage` carries `usage: {input, output, cacheRead, cacheWrite, totalTokens, cost:{input,output,cacheRead,cacheWrite,total}}` — **the full token + cost budget `agent-retro` needs**, no `entire` CLI required.
- `BashExecutionMessage` (`role:"bashExecution"`) records `command`/`output`/`exitCode` — useful for the "tool result waste" analysis.

**Implementation plan — `extract.py` pi branch:**
- Detect pi vs Claude by path prefix (`~/.pi/agent/sessions/` vs `~/.claude/projects/`) and/or by the header `type=="session"`.
- Reuse the same `--metadata-only` / `--summary` CLI interface.
- Build `conversation_arc` by walking `type:"message"` entries in `parentId` order, projecting each `message` to the same shape `extract.py` already emits (user text, assistant text + tool calls, tool results).
- Build `token_budget` / cost tables by summing `AssistantMessage.usage` across the arc.
- Build `tool_result_sizes` from `toolResult` + `bashExecution` content lengths.
- **Fallback path for `agent-retro` Step 1 (pi):** replace the Claude `~/.claude/projects/` fallback with: encode `$PWD` via pi's scheme → `ls -t ~/.pi/agent/sessions/<encoded>/*.jsonl | head -1`. Keep `entire` as the primary path if it supports pi (`entire agent add pi` — verify); otherwise the pi JSONL path becomes primary for pi roles.

This is fully implementable — the schema is public and stable (v3), and pi stores everything `agent-retro` needs inline (no external transcript service required).

---

## 5. Proposed implementation shape (revised per decisions)

1. **`swarmforge.bb :: parse-config`** — add `"pi"` to the agent whitelist; treat `advisor=` as a no-op token for pi (discard, §4.5).
2. **`swarmforge.bb :: launch-command`** — add a `pi` branch:
   ```sh
   export SWARMFORGE_ROLE='<role>' && export PATH='<worktree>/swarmforge/scripts':$PATH && cd '<worktree>' \
     && pi --append-system-prompt '<pointer-file>' --approve \
           --extension '<repo>/swarmforge/extensions/swarmforge-pi' \
           -n 'SwarmForge <Display>' <model/thinking extra-args>
   ```
   - `--append-system-prompt <pointer-file>` (pi resolves the path as a file — verified).
   - `--approve` to load `.pi/` + `.agents/` resources unattended (decision #3).
   - `--extension` loads the bundled swarmforge-pi extension (agent-running marker + % autocompaction, §4.6).
   - Model/thinking translated from extra-args: `--model provider/id`, `--thinking high` (pi syntax).
3. **`fork.bb`** — add pi-aware variants:
   - `write-persona-skill-file!` → write `.agents/skills/swarm-persona/SKILL.md` (real dir, shared by both backends); omit `AGENTS.md` from the body (pi loads it natively).
   - `write-worktree-settings!` → branch on backend: for `pi`, write `.pi/settings.json` with `swarmforge.autoCompactPct: 0.88`, `swarmforge.autoCompactWindow: 200000` (no advisor, no Claude hooks, no `permissions.allow`); for `claude`, unchanged.
   - **`install-skills!` → write into `.agents/skills/`** (both backends) instead of `.claude/skills/`. Local skills (`agent-retro`, `setup-swarm`) + pinned `entire`/`mattpocock` tarballs land in the single real dir.
   - **`write-persona-skill-file!` → write `.agents/skills/swarm-persona/SKILL.md`** (not `.claude/skills/...`).
   - **`link-curator-skills!` → generalize to `link-skills!`**: create **one directory-level symlink** `.claude/skills` → `../.agents/skills` (replace the per-skill loop; if `.claude/skills` is a real dir, `rm -rf` it first, then `ln -sfn`). Never `create-dirs .claude/skills`. No-op effect for pi (auto-discovered), keeps claude working.
4. **`swarmforge/extensions/swarmforge-pi/`** — new bundled TypeScript extension (agent-running marker + % autocompaction). Loaded via `--extension` in `launch-command` (pi only). Documented in a new ADR.
5. **`setup-swarm`** — add pi-aware steps:
   - Skip the Claude `permissions.allow` step for pi (decision #1).
   - Write `.pi/settings.json` with `swarmforge.autoCompactPct`/`Window` + the extension path (so the bundled extension reads its config).
   - **`.gitignore`: remove every `.claude` entry completely** (drop `.claude/*`, `!.claude/skills/` from the repo `.gitignore`; drop the `.claude/skills/swarm-persona/` line from setup-swarm Step 5). No `.claude*` gitignore lines remain. Swarm no longer manages Claude's gitignore surface. Resolve the generated-vs-committed split inside `.agents/skills/` (gitignore generated skill dirs by name, e.g. `.agents/skills/swarm-persona/`, while leaving curator-promoted skills committable).
   - `entire agent add pi` if `entire` supports it (verify); else document the pi JSONL fallback as the primary transcript path for pi roles.
   - The `setup-swarm` skill itself is one of the local skills installed by `install-skills!` into `.agents/skills/`, so pi loads it as `/skill:setup-swarm` via auto-discovery — **no separate install step needed**; it is available the moment `./swarm` bootstraps skills (same as claude today).
6. **`agent-retro` + `extract.py`** — add pi JSONL transcript path (pi path-encoding + v3 schema parser, §4.7). `agent-retro` is also a local skill installed into `.agents/skills/`, so pi auto-discovers it.
7. **Six-pack (and four-pack/two-pack) `swarmforge.conf` updates** — the runnable branches carry the pack configs. For the pi port:
   - **`six-pack`** (9 roles: specifier, coder, ux-engineer, cleaner, architect, hardender, QA, integrator, curator) — the canonical full workflow. Add a pi variant: either (a) a parallel `swarmforge/swarmforge.pi.conf` with `agent` column set to `pi`, or (b) keep one conf and let operators write `pi` in the agent column per-role (the parser already accepts any whitelisted agent, so mixed claude/pi/codex swarms work with no conf change once `pi` is whitelisted). **Recommended: (b)** — no new file; a six-pack operator just changes `codex` → `pi` on the windows they want. Document this in the README + the new ADR.
   - The six-pack role prompts (`swarmforge/roles/*.prompt`) are agent-agnostic — no edits needed; they're delivered via the swarm-persona bundle.
   - The six-pack curator prompt already writes to `.agents/skills/<name>/` (canonical), so it aligns with the unified skills plan in step 3 with no change.
   - **Verify on implementation:** check whether `two-pack`/`four-pack`/`six-pack` branches need the `.gitignore` + `install-skills!` path changes cherry-picked from `main` (the bootstrap copies shared scripts from `main`, but conf/roles/pack-local articles live on the branch).
8. **New ADR** — *pi backend: approve-at-launch, bundled swarmforge-pi extension, percentage autocompaction, `.agents/skills/` as the unified skill dir (claude symlinked, pi auto-discovered), advisor discarded*.

The agent-agnostic core (§1) is untouched. The work is concentrated in: `parse-config` + `launch-command` (one `case` branch), `fork.bb` (backend-branched writers + skills-dir inversion), one new bundled extension, `setup-swarm` + `agent-retro`/`extract.py` updates, six-pack conf documentation, and one new ADR.

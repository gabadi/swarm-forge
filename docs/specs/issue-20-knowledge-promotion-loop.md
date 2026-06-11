# Implementation Spec — Knowledge-Promotion Loop (issue #20)

**Status:** locked — design decisions recorded in [issue #20](https://github.com/gabadi/swarm-forge/issues/20) (see the 2026-06-11 "Definition locked" comment).
**Audience:** an implementation agent. Every file change is specified exactly. Do not redesign; where this spec and issue #20 differ, this spec wins (it encodes the locked amendments).

## Locked decisions (do not reopen)

1. **Axis (c) is a routing signal, not a discard.** A learning whose fix is global/broad routes *up* the ladder (enforcement-gate backlog or `.agents/references/`), never into `AGENTS.md`. Discard only when the gap is already mechanically closed.
2. **No capture-time pre-filter.** The retro skill captures everything (with scope tags). The curator's non-inferable check is the single discard point.
3. **The curator self-merges its knowledge PR from day one.** PR body + ledger are the async review surface.

## Delivery plan — four PRs, in order

| PR | Target branch | Content |
|----|--------------|---------|
| A | `main` | agent-retro skill upgrade |
| B | `main` | Bundle-generator knowledge injection + ADR 0001 update |
| C | `six-pack` | curator role + pipeline rewiring |
| D | `four-pack` | same as C, adapted |

Each PR is independently green. C and D must each land as one PR (role + rewiring are mutually dead without each other).

## Hard guardrails (read before any git/gh command)

- **Never** push, open PRs, or create issues against `unclebob/swarm-forge`. `gh` defaults to upstream in this repo. Run `gh repo set-default gabadi/swarm-forge` first, or pass `--repo gabadi/swarm-forge` on every `gh` call.
- `main` is documentary + shared scripts/skills only. Role prompts and `swarmforge.conf` changes go **only** on `six-pack` / `four-pack`.
- Never edit anything under `examples/`.
- Never commit `logbook.json` anywhere.
- Branch naming: `feat/issue-20-<pr-letter>-<slug>` off the target branch.

---

# PR A — agent-retro skill upgrade

**Branch base:** `main`. **File:** `swarmforge/skills/agent-retro/SKILL.md`. No other files change. `scripts/extract.py` is untouched.

Four edits:

### A1. Capture-first guard + defense-first question (Step 6)

Insert at the **top** of the `## Step 6 — Propose Actions` section, before the existing action-type list:

```markdown
Lead with the defense-first question: **"What defensive rule did this session's work absorb that future maintainers must keep intact?"** Answer it before cataloging friction — rule-shaped learnings surface before cause-shaped ones.

Capture-first guard: enumerate every candidate learning from Steps 4–5 in full before writing anything to the retro file. Do not filter for "obviousness" or "self-correcting" here — capture everything; the curation stage downstream owns discards.
```

### A2. Scope tag on every action (Step 6)

Append to the end of Step 6 (after the "Be specific…" paragraph):

```markdown
Tag every proposed action with exactly one scope:
- `project` — knowledge about the target project (its code, config, tools, conventions).
- `swarmforge` — knowledge about the harness itself (role prompts, constitution, scripts, pipeline mechanics).
- `skill` — a reusable procedure that should become or amend a skill.
- `ephemeral` — true one-offs; recorded for audit, never promoted.
```

### A3. Actions table gains Scope and Role (Step 7)

In the Step 7 template:

1. Change the metadata header block to include the role. After the `Session ID: <id>` line add:
   ```markdown
   Role: <swarmforge role name, or "interactive" outside a swarm>
   ```
2. Replace the Actions table header:
   - Before: `| # | Type | Description | Target |`
   - After: `| # | Type | Scope | Description | Target |`
   - Update the example row to match (any scope value).

### A4. Autonomous Step 8 (no human prompt in swarm runs)

Replace the entire body of `## Step 8 — Walk Through Actions` with:

```markdown
Determine the mode:

**Interactive session (a human is present):**
- Present the retro file path and summary counts (N worked, N didn't work, N actions).
- Walk through each proposed action one by one: show type, scope, description, target. Ask: "Apply? [y/n/defer]". Apply approved actions immediately; mark deferred/skipped in the table.
- After the walkthrough, show the final action table with statuses.

**Autonomous session (swarmforge role, no human in the loop):**
- Do not ask anything. Do not apply any action.
- Mark every action's status as `pending-curation` in the table and finish the retro file.
- The curator role consumes the file downstream; your only job is complete, well-tagged capture.
```

### PR A acceptance

- `grep -c 'pending-curation' SKILL.md` ≥ 1; `grep -c 'Scope' SKILL.md` ≥ 2; defense-first question present.
- The Step 7 template table has 5 columns.
- No change to Steps 1–5 or 9, no change to `extract.py`.

---

# PR B — bundle-generator knowledge injection

**Branch base:** `main`. **Files:** `swarmforge/scripts/swarmforge.sh`, `docs/adr/0001-fork-divergence.md`.

### B1. Inject knowledge files into every role bundle

In `write_agent_instruction_file()` (currently `swarmforge.sh:825`), inside the `{ … } > "$prompt_file"` block, **after** the existing `for rel in "${bundle_files[@]}"` loop and **before** `printf '</swarmforge_agent_context>\n'`, add:

```zsh
    local knowledge
    for knowledge in "AGENTS.md" ".agents/roles/${role}.md"; do
      abs_path="$WORKING_DIR/$knowledge"
      [[ -f "$abs_path" ]] || continue
      printf '<file path="%s">\n' "$knowledge"
      cat "$abs_path"
      printf '\n</file>\n'
    done
```

(`local knowledge` must be declared at the top of the function with the other locals, not inside the output block — move it accordingly.)

Also extend the preamble `printf` (the "This prompt bundle is pre-resolved…" line) by appending a second sentence to the same instruction block:

```
Project knowledge files (AGENTS.md and your role file under .agents/roles/) are included below when they exist; deep dives live under .agents/references/ and are read on demand when a included line points to them.
```

Notes for the implementer:
- `$WORKING_DIR` is the project main checkout; both files are versioned in the target project, so this is correct even though roles run in worktrees.
- Missing files are silently skipped — this is the pre-bootstrap state and must not warn or fail.

### B2. ADR 0001 update

In `docs/adr/0001-fork-divergence.md`:

1. Extend the existing **"Prompt bundle inlining at launch"** permanent-divergence section with one sentence: bundle now also appends `AGENTS.md` and `.agents/roles/<role>.md` from the project root when present (knowledge-promotion loop, issue #20).
2. Add a row to the **Proposed divergences** table:
   ```
   | V | Knowledge-promotion loop — curator role, .agents/ file contract, retro scope tags, bundle knowledge injection | issue #20 + docs/specs/issue-20-knowledge-promotion-loop.md | **Decision** — locked 2026-06-11; see issue #20 comment |
   ```

### PR B acceptance

- Launch a swarm against a scratch project containing an `AGENTS.md`: every generated `.swarmforge/prompts/<role>.md` contains a `<file path="AGENTS.md">` block.
- Add `.agents/roles/coder.md` to the scratch project: only the coder bundle gains that block.
- Remove both files: bundles generate cleanly with no knowledge blocks and no errors.

---

# PR C — curator role + rewiring (six-pack)

**Branch base:** `six-pack`. **Files:** `swarmforge/roles/curator.prompt` (new), `swarmforge/swarmforge.conf`, `swarmforge/roles/integrator.prompt`, `swarmforge/roles/specifier.prompt`, `swarmforge/constitution/workflow.prompt`.

### C1. swarmforge.conf

Append as the **last** line (the first window is the cleanup window and must stay first):

```conf
window curator codex curator
```

### C2. curator.prompt (new file — exact content)

Create `swarmforge/roles/curator.prompt` with exactly this content:

```markdown
You are the curator.

Wait for a handoff. Do not act without one.

- Own the knowledge-promotion stage: turn retro actions into versioned repo knowledge via one self-merging PR per run.
- Make no code changes. You may only create or edit: `AGENTS.md` and files under `.agents/`.
- The pipeline must never stall on you. Whatever happens, the specifier gets notified at the end of every run.

## Sources

Unprocessed retro files: `~/.claude/worklog/retros/*.md` (files directly in that directory; `processed/` holds finished ones). Each retro carries `Session ID`, `Role`, and an Actions table where every action has a scope tag: `project | swarmforge | skill | ephemeral`.

## Targets — the routing ladder (top rung wins; promote to the highest rung that fits)

1. **Enforcement-gate backlog** — if the fix can be mechanical (a config line, CI gate, script guard), append a dated proposal to `.agents/backlog.md`. A gate beats documentation.
2. **`AGENTS.md`** — navigation map + universal invariants only. Hard cap 60 lines. One line per rule: rule + reason inline.
3. **`.agents/roles/<role>.md`** — operational knowledge for one role. Cap 40 lines. Create lazily, only when the first promotion for that role arrives.
4. **`.agents/references/<topic>.md`** — deep dives. Unbounded, but every reference must have a pointer line in `AGENTS.md` or a role file, or it will never load.
5. **`.agents/skills/<name>/`** — procedures. Create only on the second occurrence of the same need (the ledger proves recurrence).
6. **`.agents/upstream/<date>.md`** — swarmforge-scoped items; one report per run when non-empty. Consumed by the swarm-forge triage loop.
7. **Ledger only** — ephemeral, rejected, and discarded items.

`.agents/ledger.md` is the append-only audit. One line per processed item, never pruned:

```
<date> | <session-id> | <role> | <failure-class> | <verdict> | <one-line summary>
```

- `failure-class` ∈ `missing-artifact | wrong-path | verifier-failure | tool-error | timeout | oscillation | convention-gap`
- `verdict` ∈ `promoted→<file> | rejected→<reason> | upstream | ephemeral`

## Lifecycle

1. Receive handoff from the integrator (specifier handoff name + commit hash). No handoff — including cold launch — means idle.
2. Sync: `git fetch origin && git merge --ff-only origin/master` in your assigned worktree.
3. Collect unprocessed retro files. **Empty run:** no PR, no commits — skip to step 9 immediately.
4. Create the knowledge branch: `git checkout -b knowledge/<specifier-handoff-name> origin/master`.
5. **Bootstrap:** if `AGENTS.md` or `.agents/ledger.md` does not exist, create it on this branch (empty ledger header; AGENTS.md with a `# AGENTS.md` title only).
6. Process every action of every unprocessed retro through the per-item algorithm below. Every item gets a ledger line — including discards.
7. Enforce budgets: AGENTS.md ≤ 60 lines, role files ≤ 40. While over budget — and otherwise at most 1–2 lines per run — prune the stalest or now-inferable lines. Ledger every prune as `rejected→pruned-stale`.
8. Land the PR: commit, push the knowledge branch, `gh pr create`, then `gh pr merge --delete-branch --squash` once checks pass — self-merge is an in-role action; no user confirmation. The PR body must contain: the metric line `promoted: N | rejected: N | upstream: N | ephemeral: N (totals: P/R/U/E)` (running totals computed from the ledger) and one bullet per promoted line quoting it verbatim. Check out back to your assigned worktree before merging.
9. Move all processed retro files to `~/.claude/worklog/retros/processed/` (create the directory if absent).
10. Notify the specifier per workflow rules. Branch name `master`; commit hash = current `origin/master` HEAD after your merge (on an empty run, the hash from the integrator's handoff).
11. Run `agent-retro` before going idle.

## Per-item algorithm

Apply in order; the first failing check decides the verdict.

1. **Scope routing:** `ephemeral` → ledger only, stop. `swarmforge` → upstream report, stop. `skill` → check the ledger for a prior occurrence of the same need; first occurrence → ledger as `rejected→first-occurrence`, second → create the skill. `project` → continue.
2. **Recurrence check:** search the ledger for the same failure. Previously `rejected` and now recurring → it has proven itself non-trivial: promote a one-line rule (project knowledge) or escalate to the upstream report (harness-generic), do not reject again.
3. **Non-inferable check:** could a future agent reach this fix from the error output and the files it names, with no foreknowledge? If yes → `rejected→inferable`. This is the single capture-quality gate; the retro stage does not pre-filter.
4. **Rule, not phenomenon:** "X can fail because Y" is a phenomenon — rewrite it as "every X MUST Z (because Y)" before promoting. If no rule form exists, `rejected→phenomenon`.
5. **Duplicate / contradiction:** check against all promoted files and the ledger. Duplicate → `rejected→duplicate`. Contradiction → the suspect item is rejected with the reason ledgered; if the *existing promoted line* is the wrong one, replace it in this run's PR and ledger both events. Never promote a suspect item; never park it.
6. **Global-fix routing (axis c):** if the fix covers all future analogous work (global config, harness-wide gate), do not discard — route to the enforcement-gate backlog (rung 1) or a reference (rung 4) instead of `AGENTS.md`. Reject only if the gap is verifiably already closed (the config/gate exists — check).
7. **Routing + trigger-load fit:** will the target file actually be loaded when this knowledge is relevant? `AGENTS.md` loads for every role; a role file loads for that role only; a reference loads only via pointer. If the fit fails, move one rung and re-check.
8. **Evidence pull (selective):** for load-bearing or suspicious claims only, verify against the repo before promoting (read the config, run the one-liner). Unverifiable load-bearing claim → `rejected→unverified`.
9. **Sizing:** minimal-first — one line carrying rule + reason. A reference file only when one line genuinely cannot hold it.
```

### C3. integrator.prompt

Replace lifecycle step 7:

- Before: `7. Notify the specifier that the feature has landed.`
- After: `7. Notify the curator that the feature has landed. Include the specifier handoff name and the post-merge master commit hash.`

### C4. specifier.prompt

Replace the line:

- Before: `- When the integrator notifies you that the job is complete, ask the user for the next feature to add.`
- After: `- When the curator notifies you that the job is complete, first run the startup sync (fetch + ff-only merge), then ask the user for the next feature to add. The curator's handoff means the knowledge PR for the previous feature has already landed on master.`

### C5. workflow.prompt

Append one bullet at the end of `# Workflow Rules`:

```markdown
- The landing chain is: integrator → curator → specifier. The curator promotes retro knowledge into the repo before the specifier is released; an empty curation run notifies the specifier immediately — the pipeline never stalls on the curator.
```

### PR C acceptance

- `./swarm` launches 9 windows; curator window appears last; cleanup window unchanged (specifier first).
- `notify-agent.sh curator "<msg>"` from the integrator worktree delivers (window/session name resolves).
- Grep checks: integrator.prompt no longer notifies specifier; specifier.prompt references curator; workflow.prompt documents the chain; `curator.prompt` exists and is referenced by no BFS-bundled file other than itself (the conf, not prompt references, wires it — this is expected and correct).

---

# PR D — same on four-pack

**Branch base:** `four-pack`. Identical changes to PR C with these adaptations:

- `swarmforge.conf` (5 existing windows) gains the same last line: `window curator codex curator`.
- `curator.prompt`: byte-identical to PR C's file. It is role-count agnostic.
- `integrator.prompt` step 7: same edit as C3 (the four-pack integrator's step 7 has identical wording).
- `specifier.prompt`: apply the same edit as C4 (find the integrator-notifies line; wording on four-pack may differ slightly — match on "integrator notifies you").
- `workflow.prompt`: same appended bullet as C5.

### PR D acceptance

Same checks as PR C, with 6 windows total.

---

# End-to-end definition of done (after all four PRs)

Run one real feature through a target project (tetris is the reference). Done means:

1. The knowledge PR merged **before** the specifier was released for the next feature.
2. Every retro action from that cycle has a ledger verdict (including discards).
3. Budgets held: `wc -l AGENTS.md` ≤ 60; every role file ≤ 40.
4. Empty-run path verified: a cycle with zero unprocessed retros notifies the specifier with no PR and no stall.
5. Fresh-clone test: a clean checkout shows all promoted knowledge; nothing depends on `~/.claude` local memory.

## Loop health (carried by the curator, no extra build work)

Each curator PR body carries the metric line. Kill criterion: fewer than 3 promotions that survive contact with later sessions over 90 days → disable the curator window; ledger and promoted docs stay.

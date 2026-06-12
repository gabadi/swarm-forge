# Factory Line Refactor — Proposal & Decision Log

**Date:** 2026-06-11
**Status:** draft for review — captures a full critique session of the fork (engine + agents), including framings that were corrected or rejected along the way. Nothing here is implemented.
**Source:** deep-dive over `main` (scripts, ADR 0001, CONTEXT.md), `four-pack`/`six-pack` (constitution, all role prompts, `./swarm`), the agent-retro / retro-triage skills, and the issue #20 curator spec.

---

## 1. The question that started this

> Is this pipeline really valuable, or is it complexity that could be solved with a skill or similar simpler mechanism?

**Final verdict (end of session): the pipeline survived the audit.** Its shape, ordering, artifacts, and doctrine are right. What the critique found was:

1. One substantive quality gap: **QA confirms instead of refutes** — the only change with real quality value.
2. Trust-placement debt: things enforced by prompts that should be enforced by code — functionally equivalent until it breaks, and the repo's own incident history shows it breaks.
3. One cost hypothesis: cleaner/architect/hardener may be one role, not three — to be decided by experiment, not argument.

---

## 2. Key observations (evidence-backed)

- **The fork's own trajectory argues against its substrate.** Every divergence (Ideas A/B/D: `/clear` + bundle re-inject per task, `git reset --hard` per task, idle gates, harness-owned logbook) strips persistence from the "persistent agents." Each role is now functionally a stateless function: `(bundle, message, hash) → (hash, message)`. That is exactly a fresh headless invocation. The tmux layer exists to emulate statelessness on top of statefulness.
- **Tetris batch is the controlled experiment on the role topology.** Two user-visible defects survived 8 roles and 250 tests because every role shared the same blind spot (nobody drove the real binary). Eight serial passes by agents with the same method/artifacts/model are **correlated reviewers** — N correlated reviewers ≈ 1 reviewer.
- **Every fix that worked was a gate, not a role.** Ideas P/Q/T (observation harness, conversion fidelity, evidence-as-code) converted role obligations into artifacts + downstream checkers. Pattern: **roles assert; gates verify.**
- **The maintenance tax of prompt-placed trust is visible in git history:** logbook corruption incident (tracked file + `reset --hard`), checkpoint-skipping hacks, "do not execute prompt on agent startup," depth tracked via PR-comment archaeology, sleep-based send-keys with no delivery ack.
- **Prompt-layer drift signs:** `hardender` typo institutionalized; `project.prompt` says "eight Codex-backed agents" (drift); handoffs open with "Re-read your role and constitution" while the bundle preamble forbids re-reading prompt files; magic thresholds (CRAP ≤ 6, 100 / 15–20 mutation sites, N=3) have no recorded calibration.
- **The pipeline is sequential** — one role works, the rest idle. Per-role worktrees solve a parallelism problem the workflow doesn't have.
- **QA today** fixes bugs, re-runs CRAP/DRY (third+ time in the pipeline), and is framed to *confirm* ("verify the specification").
- **Curator trust record:** two prior auto-filed retro batches closed as mis-framed; `Validated:` stamps were forged without receipts. Capture quality does not yet earn unconditional trust — but autonomy is a hard requirement (see §4).
- **Vendor heterogeneity (claude/codex/copilot/grok per role) is the substrate's one real moat.** Preserved in the proposal via headless CLI spawns; never at risk.

---

## 3. Framings proposed and CORRECTED during the session

Recorded so we don't relitigate them tomorrow.

| Initial framing | Correction | Why |
|---|---|---|
| "Substrate vs doctrine" | Real axis: **who owns control flow — prompts or code** | The tmux question is downstream of routing ownership |
| "Replace the whole thing with a workflow/skill" | It's a **workbench**, not a batch job — the specifier is genuinely interactive (approval gates, clarifying questions) | One interactive seat, the rest autonomous |
| "Replace tmux with flue" | **tmux isn't replaced — its need disappears.** Nothing persistent remains except the orchestrator; stages are spawned processes; watching = `tail -f` per-stage logs | flue is optional; the requirement is routing-in-code, and the state is 4 variables — below framework threshold. flue buys durability/observability at the price of a TS runtime in a zero-dependency system |
| Merge ux-engineer + QA into one verifier | **Rejected — ux-engineer is a builder, not a verifier** (user: UX modifies a lot of code; placement after coder is correct and was settled by batch evidence). UX keeps authoring scenarios; only the independent re-execution belongs to the verifier | Builder vs verifier is the right cut, not "both touch UX" |
| Integrator → pure script | **Rejected — integrator must be a model** (user), CI-log diagnosis is judgment. Compromise: **cheap model (haiku-class) for the verdict; the orchestrator executes the merge on its green verdict** | Judgment from the model, irreversible action from code |
| Human gate on curator PRs | **Rejected — curator must be automatic** (user, hard constraint). Compromise: gate the **artifact** mechanically in CI, not the agent | Same doctrine: mechanical gates over trust |
| Model diversity at verifier as a counted change | **Ruled out of the proposal by user: it's configuration, not process.** Remains available via Idea U conf keys | Don't count config knobs as pipeline changes |
| "The proposal changes a lot" | User challenge sustained: **on the org chart, only the QE merge changes boxes.** The substantive changes are mandates, permissions, and trust placement — and that's the finding, not an omission: the cast was right, the trust model was wrong | |

---

## 4. The proposal — four changes, ranked by value

### 4.1 QA → adversarial **verifier** (the only substantive quality change — CONFIRMED, ship first)

- Builds nothing, fixes nothing. Mandate inverts from *confirm* to **refute**: "attempt to refute the feature through the declared surface harness; document each refutation attempt."
- Removes QA's fix authority and its redundant CRAP/DRY runs.
- Re-executes `observation-harness/` scenarios independently (Idea T mandate kept).
- **This is a `QA.prompt` rewrite on `six-pack` — no engine work, no topology change, no dependencies. No reason to wait.**
- (Different vendor/model at this seat is available via Idea U conf keys — configuration, not part of the process change.)

### 4.2 Routing moves from prompts to code (maintenance-tax paydown, not a pipeline change)

- One orchestrator process — the only long-running thing (flue-shaped or a ~100-line script).
- Stage = fresh headless spawn (`claude -p` / `codex exec` / `copilot -p`) with the existing resolved bundle. Vendor/model per role from `swarmforge.conf`, unchanged.
- Hash-in/hash-out handoff contract unchanged (best part of the current design).
- Agents end runs with a structured verdict (`pass` | `defect → owner + repro`); the orchestrator routes and owns the depth counter (replaces PR-comment counting).
- State = `(feature, stage, hash, depth)` in one file.
- Deleted as a consequence: logbook.json, stop hooks, deliver/notify scripts, watchdog, terminal adapters, worktrees, `/clear`+`/rename` dance — ~800 of 1,100 lines of zsh and the harness-self-repair commit class.
- Prompts shrink to pure craft rules (all notify/queue/merge plumbing removed) — this is also what makes roles cheap to A/B.
- Specifier runs interactively in the operator's terminal (the one interactive seat).

### 4.3 Trunk access mechanically gated (safety, not a pipeline change)

- **Integrator:** stays a model, cheap tier. Diagnoses CI reds and routes by table. The standing `gh pr merge` permission moves out of the agent — the orchestrator merges on the integrator's green verdict.
- **Curator:** fully automatic (hard requirement), made safe by CI gates on the PR:
  - path allowlist — touches anything outside `AGENTS.md` + `.agents/` → auto-reject
  - line caps (150/300) enforced by script, not curator discipline
  - receipt check — every promoted line carries a commit SHA or session ID
  - ledger lint (format check)
  - drift alarm — a promoted rule named in a later failure retro → auto-flagged for prune
  - one-squash-per-run → rollback is a single revert

### 4.4 QE merge: cleaner + architect + hardener → one **quality-engineer** (cost optimization — HYPOTHESIS, experiment-gated)

> **SUPERSEDED by §9 (2026-06-12 session): the architect is excluded from the merge.** Only cleaner + hardener merge. See §9 for the full rationale and the architect's redefined mandate.

- Rationale: all three do behavior-preserving structural work; CRAP/DRY/mutation appear in all three prompts; the tools enforce the checklist, so three personas aren't needed to remember it.
- **Dual mode:** fixes behavior-preserving issues itself (renames, splits, boundary extraction, killing mutation survivors via tests); behavior defects → verdict back to coder (today's Idea E line, routed by the orchestrator).
- **The only step that ships on data, not argument** — see §6.

### Resulting line

```
specifier ─► coder ─► ux-engineer ─► quality-engineer ─► verifier ─► integrator ─► curator
(interactive) └──── build ────┘        (structural)     (adversarial)  (cheap)      (auto)
```

Exit gates, all machine-checked: user approval → unit+acceptance green → scenarios exist+pass → CRAP/DRY/mutation/arch-check green → scenarios re-run green + refutation documented → CI green → curator CI gates.

### Preserved unchanged

Evidence-as-code doctrine, fidelity manifest, UX-after-coder ordering, specifier approval gates, depth caps (N=3), hash-only handoffs, knowledge-promotion ladder, vendor heterogeneity, feature template (7 sections + UX Intent), constitution structure.

---

## 5. Migration — independently shippable steps

1. **Verifier prompt rewrite** (`QA.prompt`, six-pack). Ships now.
2. **Integrator on cheap model; merge action moved to code.** Removes the riskiest standing permission.
3. **Curator CI gates → safe auto-merge.** No role change.
4. **Orchestrator transport.** Current prompts run headless per stage, lineup unchanged; "notify X" lines go inert, then get stripped; tmux layer retires here.
5. **QE merge** — only after the experiment (§6).

---

## 6. The validation experiment (decides step 5)

After step 4 the lineup is just a stage list in config, so **both topologies run on the same engine.** Push the same ~3 features through:

- (a) the current 8-role line
- (b) the proposed 6-role line (QE merged)

Compare: escaped defects, back-route cycles, cost. The retro/cost instrumentation already captures all three. If (a) catches defects (b) misses → keep the split; the merge dies. Role count becomes a measurement, not a belief.

---

## 7. Final synthesis (agreed at end of session)

- Changes **1 (verifier)** = the real quality value. Small adjustment, confirmed.
- Changes **2 + 3 (routing in code, gated trunk access)** = code-vs-prompt tradeoff; functionally the same pipeline; schedule as **debt paydown**, justified by the incident history, not as features.
- Change **4 (QE merge)** = optimization, experiment-gated.
- **The pipeline itself is what we need.** The critique validated it.

## 8. Open questions for tomorrow

> Several of these are resolved by §9: the four-pack question inherits the architect mandate (§9.4–9.8); the verifier's refutation artifact remains open; drift-alarm mechanics are extended to arch rules (§9.14).

- Orchestrator host: plain script vs flue (durability/observability vs TS dependency). Decision deferred.
- Does the verifier rewrite also apply a reduced form to `four-pack` (which has no QA role — its architect is terminal)?
- Where does the verifier's "refutation documented" artifact live — handoff summary vs committed file?
- Drift-alarm mechanics for curator gates: who scans later retros for promoted-rule mentions (CI job vs curator's own next run)?
- Step 2/3 ordering vs step 4: gates currently assume GitHub CI exists in target projects — confirm minimum CI assumptions.

---

## 9. Amendment — 2026-06-12 session (architect carve-out + gate/knowledge model)

This session challenged §4.4 and the "agents → gates" framing. Conclusions, each standing on its own:

### Topology

1. **Cleaner + hardener merge into one quality-engineer; the architect stays a separate seat.** The §4.4 rationale ("the tools enforce the checklist") holds for cleaner and hardener — same tools in count-mode, run-mode, and re-check-mode is genuine redundancy — but the architect is the one seat in the trio doing open-ended judgment with no tool behind it. Merging it dilutes the only ungated work in the pipeline.
2. **Resulting line (7 seats):** specifier → coder → ux-engineer → **architect** → **quality-engineer** → verifier → integrator → curator. The QE sits *after* the architect: "harden last, on final shape" is kept; pre-architect cleanup is sacrificed (cheapest loss, and the one the §6 experiment can actually detect, as back-route cycles).

### Gates

3. **Per-stage exit gates, executed by the orchestrator.** Each stage is gated only on what it promised — not every check at every boundary. Agents still run tools locally to iterate; the run that advances the pipeline is the orchestrator's (dev-runs-tests-locally / CI-decides relationship).
4. **Gate map:** coder = unit+acceptance green · ux = scenarios exist+pass · architect = arch-check green + (rules diff ∨ explicit ruling) · QE = CRAP/DRY/mutation green (mutation runs **once**, here) · verifier = scenarios re-run green + refutation documented · integrator = CI green, orchestrator executes the merge · curator = CI gates (path allowlist, caps, receipts).
5. **Arch-check is the only gate cheap enough to run at every exit from coder onward** (static analysis, seconds) — a boundary violation is caught in the turn that created it, not two stages later.

### Architect mandate (redefined)

6. **Deliverable inverts: rules, not corrections.** Every architect turn ends with arch-rule changes or an explicit ruling ("no rule change — feature stayed inside existing boundaries"). The restructuring diff is the side effect. "When practical" becomes mandatory; an empty turn (no rules, no ruling) is mechanically rejected by the gate.
7. **New rules land green via freezing, never red.** A born-red rule ships frozen with a committed baseline of existing violations. Gate semantics: *no new violations ∧ baseline did not grow this feature*. Green at every handoff — no "allowed red" phase, no zero-debt requirement at integration. The QE burns the baseline down across features. The ratchet, not the cliff.
8. **Custom rules: unrestricted in content, fixed in form.** The contract is not "use dependency-cruiser" — it is "a rule counts if it is executable." Off-the-shelf tools (dependency-cruiser, import-linter, ArchUnit) cover imports/cycles/layers; everything else is semgrep/ast-grep patterns or small scripts in an `arch-checks/` dir the gate runner executes wholesale. Required form: executable, fast, deterministic, baseline-able. The architect is an **author of linters**, not a user of them.
9. **Friction input:** the structured verdict gains an optional `friction` array (e.g. "touched 9 files for one behavior change", "couldn't test X without live DB"). The orchestrator accumulates it per feature and injects it into the architect's bundle. No retro reading — that stays the curator's job.
10. **Steady state:** after the bootstrap turn (pick tools, encode current boundaries), most architect turns are short rulings. The seat becomes a cheap legislator — restructuring only when friction trends say a boundary is wrong. A cheap seat removes the last cost argument for merging it.

### Knowledge ladder

11. **Three rungs:** AGENTS.md prose → `.agents/skills/` authoritative review skills → `arch-checks/` executable rules. Knowledge climbs as it stabilizes. Reference shape: Addi's `reviewing-openapi-specifications` skill, which explicitly splits judgment-layer review (URL design — ~60% of real review comments, unlintable) from mechanical rules that already graduated to build tooling.
12. **Ownership:** curator owns prose→skill promotion (`.agents/` is already inside its path allowlist; a skill extraction is a bigger promotion under the same receipts and CI gates). Architect owns skill→check codification (codify-candidates) and flags judgment-heavy structural lessons downward as skill-candidates.
13. **Curator ↔ architect never communicate directly.** Codify-candidate and skill-candidate flags ride existing artifacts.
14. **Drift alarm runs the ladder downward too:** a rule accumulating exceptions or named in failure retros is auto-flagged for prune — same treatment as curator ledger lines. Bad judgment becomes visible as rule churn.

### Scope guard

15. **Net new machinery — exhaustive list:** `arch-checks/` dir + one gate-runner line, the `friction` field, two flag labels. Everything else reuses the curator ladder, bundle injection, receipts, CI gates. Explicitly NOT built: skill registry, rule-effectiveness scorer, "did the seat really use the skill" enforcement, any new communication channel. If one of those ever feels necessary, the rule should move up a rung instead.
16. **Experiment limits acknowledged:** §6 validates the cleaner+hardener merge (back-route cycles show within ~3 features) but **cannot judge the architect** — architectural decay doesn't surface as escaped defects in that window. The architect's quality signals are slower and different: baseline trend, rule churn, change amplification (files touched per feature), coder cycle time.

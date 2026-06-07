# Idea M — UX Intent in the SwarmForge Pipeline

**Status:** Proposed  
**Source:** GitHub issue #2 (closed — captured locally)

## Context

### The pipeline today

SwarmForge runs agents in sequence (four-pack or six-pack). Each role owns a quality gate: behavioral correctness (specifier/coder), cleanliness (refactorer/cleaner), structure (architect), hardening (hardener/architect), and verification (QA). This pipeline produces high-confidence behavioral correctness.

### The problem

The pipeline has no concept of UX. "UX" here means four concrete, specifiable things:

1. **Visual Composition** — layout structure, panel arrangement, character vocabulary, rendering across all game states
2. **Information Hierarchy** — what the user's eye goes to first, what is prominent vs. secondary, reading order
3. **Interaction Feel** — key response timing, feedback on blocked actions
4. **State Transitions** — what changes and how between every state pair

Consequences:
- **The coder makes all UX decisions alone.** Every layout, character, and spacing decision is made by the agent using training-data defaults.
- **UX intent written by the specifier never reaches the coder.** The coder prompt excludes the QA suite from its inputs; intent travels specifier → QA with no intermediate agent reading it.
- **No quality tool has UX signal.** CRAP, DRY, and mutation have no bearing on whether `View()` renders correctly.
- **The cleaner can accidentally break UX.** It splits functions for CRAP reasons with no instruction to preserve visual composition.
- **QA catches what was written, not what was missed.** If the suite has weak UX assertions, QA produces weak tests.

### Why Gherkin alone is insufficient for UX

Gherkin maps well to behavioral happy paths. It structurally cannot express visual hierarchy, affordances, interaction quality, or emotional goals. This is a grammar mismatch — extending Gherkin would produce a different DSL that loses its testability contract.

## Decision

Three prompt extensions and one new role. All changes are **six-pack only** — four-pack has no hardener, no UX Reviewer, and no QA, so the UX pipeline has no home there.

### 1. Specifier — add UX Intent authoring (six-pack only)

Add a step 0 before the existing phases:

> Before writing Gherkin, author a `## UX Intent` section in the QA suite covering four subsections: Visual Composition, Information Hierarchy, Interaction Feel, and State Transitions. Write each as concrete observable statements, not subjective preferences.

**Rationale:** Visual composition, interaction feel, and state transitions are externally visible — the same kind of observable statement the specifier already writes. UX intent must be settled before the coder touches anything.

**Tradeoff:** If the user provides weak or missing UX intent, the specifier produces weak UX sections. The pipeline formalizes intent; it cannot originate it.

### 2. Coder — read and implement from UX Intent (six-pack only)

Add one instruction:

> Implement from the feature file and the QA suite's UX Intent section. The UX Intent section specifies visual composition, information hierarchy, interaction feel, and state transitions that the implementation must satisfy alongside behavioral correctness.

**Rationale:** The coder currently ignores the QA suite entirely. This exclusion is why UX intent never influences implementation. Removing it for the UX Intent section (preserving it for procedural QA steps) is the minimal change.

**Tradeoff:** Two sources of guidance that could conflict. The specifier must ensure UX Intent and Gherkin are consistent. If they conflict, the coder stops and reports.

### 3. Hardener — add rendering property tests (six-pack only)

Add one instruction:

> For pure rendering functions (functions that map state to string output with no side effects), add property tests covering output invariants: required structural elements always present for their respective states, character set bounded to declared vocabulary, mutually exclusive states never co-rendered.

**Rationale:** Mutation operates on logic branches; `View()` is pure string construction. A mutation that drops the stats panel may survive all current tests. Property tests over `View()` close this gap.

**Tradeoff:** Property tests that are too strict about structure will break on legitimate future layout changes. Invariants should be structural (board always has borders) not positional (score appears at column 47).

### 4. UX Reviewer — new role between hardener and QA (six-pack only)

The UX Reviewer is added to six-pack only. Four-pack has no hardener or QA, so no placement exists. The full six-pack pipeline with integrator (Idea C):

```
specifier → coder → cleaner → architect → hardener → UX Reviewer → QA → integrator → (notify specifier)
```

**Mandate:** Run the binary. Read the UX Intent section. Compare live experience against each statement. Report mismatches as defects with specific reference to the UX Intent statement violated. No code changes — judgment and reporting only.

**Rationale:** Every other role executes against written criteria. The UX reviewer makes a judgment call: does this feel right? That requires an agent that runs the software and experiences it. This is distinct from QA (which verifies implementation matches spec) — the UX reviewer checks that what was written was the right thing.

**Tradeoff:** Adds a pipeline stage. For features with no UX component, the UX reviewer passes through immediately (existing "no changes → don't hand off" rule). Quality of UX review is directly coupled to quality of UX Intent authoring.

**Files changed (six-pack only):**
- `six-pack`: `swarmforge/swarmforge.conf` — add UX Reviewer window between hardener and QA
- `six-pack`: `swarmforge/roles/ux-reviewer.prompt` (new)
- `six-pack`: `swarmforge/roles/specifier.prompt` — add UX Intent authoring step
- `six-pack`: `swarmforge/roles/coder.prompt` — add UX Intent reading instruction
- `six-pack`: `swarmforge/roles/hardener.prompt` — add rendering property tests instruction

## Consequences

**What improves:**
- UX intent travels from user → specifier → coder → hardener → UX reviewer → QA without any agent inventing it
- Rendering correctness is mutation-hardened via property tests
- QA assertions become specific and verifiable

**What does not improve:**
- Color and terminal styling remain unverifiable through `tmux capture-pane -p` (ANSI codes stripped)
- Information Hierarchy is partially unverifiable — "Score is the most prominent stat" cannot be asserted by a string capture test
- If the user provides no UX intent, the pipeline produces no UX value

## Alternatives considered

**Single `## Visual Composition` section only:** Does not cover Information Hierarchy, Interaction Feel, or State Transitions. Rejected as insufficient.

**Extend QA to include experiential judgment:** Mixes verification against spec (objective) with experiential judgment (subjective). Ambiguous failures. Rejected.

**Dedicated UX Designer role before specifier:** Overengineered for this pipeline's scale. The specifier already owns observable behavior specification; UX Intent is observable behavior. Rejected.

**DESIGN.md (Google format):** Targets web UI design tokens (hex colors, font families). Does not cover this pipeline's relevant vocabulary (character sets, panel positions, ANSI codes) or Information Hierarchy, Interaction Feel, State Transitions. Rejected as primary mechanism.

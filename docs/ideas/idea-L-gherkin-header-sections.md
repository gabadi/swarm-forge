# Idea L — Gherkin Header Sections

**Status:** Proposed  
**Open question:** Which sections? (Challenged from 7 to ~3 — specific 3 not yet decided)

## Context

Gherkin's Given/When/Then grammar reliably captures behavioral happy paths. Analysis of real PRs in swarm-driven projects shows that specs systematically omit certain categories of information, leading to implementation gaps that only surface in QA or production:

- **Response contracts** — error codes, edge-case response shapes, boundary conditions
- **Explicit exclusions** — what is intentionally NOT in scope for this feature
- **Side effects** — other systems or contracts that must be updated when this behavior changes

The specifier writes Gherkin scenarios from user intent. Without explicit prompting for these categories, the specifier (and the user providing intent) focuses on the happy path and omits the categories above consistently.

Melech's approach (D40) mandates a seven-section header (`TRACKING`, `CONTRACT`, `CONSTRAINTS`, `SEQUENCING`, `NFR`, `SIDE EFFECTS`, `SCOPE`) immediately after the `Feature:` line. Seven is too many — most sections will be `# SECTION: none` for most features, making the header ritual rather than substantive.

## Decision (draft — sections not finalized)

Add a mandatory header to every feature file with ~3 sections addressing the most consistently missing categories. Each section with nothing to say is written as `# SECTION: none` — the section must be present but can be empty.

**Candidate sections (decide which 3):**

| Section | What it captures | Gap it fills |
|---|---|---|
| `CONTRACT` | Exhaustive response shapes, error codes, boundary conditions | Most consistently missing; coder makes up error responses |
| `SCOPE` | Explicit exclusions — what is NOT included | Prevents scope creep; assumptions explicit |
| `SIDE EFFECTS` | Other system contracts updated by this behavior | Prevents silent contract breakage in adjacent systems |
| `CONSTRAINTS` | Data scope, field availability, bounded inputs | Overlaps with CONTRACT — may not be needed separately |
| `SEQUENCING` | Async ordering obligations | Only relevant for async flows — too specific |
| `NFR` | Idempotency, latency, observable states | Rarely relevant at feature level |

Recommendation: **CONTRACT + SCOPE + SIDE EFFECTS** — the three that address consistently missing information across the widest range of feature types.

**Files changed:**
- `swarmforge/constitution/engineering.prompt` — mandatory header rule
- `swarmforge/roles/specifier.prompt` — add header authoring step before writing scenarios
- New `swarmforge/templates/feature.feature` — rubric-based template with prompting questions per section

**Minimal diff from upstream:** The template is additive. The specifier prompt change is one step added to the existing lifecycle. `engineering.prompt` gains one rule. No upstream content removed.

## Open questions

**Which 3 sections?** This must be decided before implementation. CONTRACT + SCOPE + SIDE EFFECTS is the current recommendation — needs explicit confirmation.

**How strict is enforcement?** Options:
1. Specifier prompt rule only — agent is asked to include the header
2. `notify-agent.sh` harness validates the feature file has the header before accepting a specifier handoff
3. A linting step in the verification suite

Option 1 is minimal diff. Option 2 requires the harness to know about feature file format (coupling concern). Option 3 is most robust but requires a new project-level script. Start with Option 1.

## Alternatives considered

**Seven sections (melech D40):** TRACKING, CONTRACT, CONSTRAINTS, SEQUENCING, NFR, SIDE EFFECTS, SCOPE. Most sections are `none` for most features — the header becomes ritual. Rejected — three focused sections produce more signal per character than seven diluted ones.

**No header — rely on the specifier to cover edge cases in scenarios:** Current behavior. The systematic omissions are real and reproducible; relying on the specifier to self-correct has not worked. Rejected.

**Extend Gherkin syntax to express contracts:** A grammar mismatch — Gherkin's testability contract depends on Given/When/Then mapping to executable steps. A CONTRACT section as structured prose alongside Gherkin is cleaner than extending the grammar. Rejected.

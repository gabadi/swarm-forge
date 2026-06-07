# Idea L — Gherkin Header Sections

**Status:** Proposed

## Context

Gherkin's Given/When/Then grammar reliably captures behavioral happy paths. Analysis of real PRs in swarm-driven projects shows that specs systematically omit certain categories of information, leading to implementation gaps that only surface in QA or production:

- Response contracts — error codes, edge-case response shapes, boundary conditions
- Explicit exclusions — what is intentionally NOT in scope for this feature
- Side effects — other systems or contracts that must be updated when this behavior changes

The specifier writes Gherkin scenarios from user intent. Without explicit prompting for these categories, the specifier focuses on the happy path and omits the categories above consistently.

## Decision

Add a mandatory 7-section header to every feature file, immediately after the `Feature:` line. Each section must be present; sections with nothing to say are written as `# SECTION: none`.

The template (`swarmforge/templates/feature.feature`) is adopted from melech-mini-apps as-is, with rubric questions and format guidance per section:

| Section | What it captures |
|---------|-----------------|
| `TRACKING` | Issue reference — traces work to a tracked issue or story |
| `CONTRACT` | All inputs, all response shapes and status codes including every error |
| `CONSTRAINTS` | Data scope bounds, unavailable fields, validation rules, exclusion filters |
| `SEQUENCING` | Async ordering obligations — operations that must run in specific order |
| `NFR` | Latency/throughput targets, idempotency key, in-flight display, error distinguishability |
| `SIDE EFFECTS` | Public-facing contracts added/removed/changed; derived artifacts to regenerate |
| `SCOPE` | Explicit exclusions — what this feature does NOT do; unstated assumptions flagged |

**Files changed:**
- `four-pack` + `six-pack`: `swarmforge/templates/feature.feature` (new) — 7-section rubric template
- `four-pack` + `six-pack`: `swarmforge/roles/specifier.prompt` — add step: "start from `swarmforge/templates/feature.feature`; complete all seven header sections before writing scenarios"

**Minimal diff from upstream:** The template is additive. The specifier prompt change is one step added to the existing lifecycle.

## Alternatives considered

**Three sections (CONTRACT + SCOPE + SIDE EFFECTS):** Addresses the most common gaps but leaves TRACKING, CONSTRAINTS, SEQUENCING, and NFR without prompting. The melech-mini-apps implementation with all 7 sections proves the full set is necessary and usable. Rejected.

**No header — rely on the specifier to cover edge cases in scenarios:** The systematic omissions are real and reproducible. Rejected.

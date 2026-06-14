---
status: accepted
---

# Live verification runs through a declared surface harness

Two defects (a screen blink and a runaway key-repeat) once survived a 250-scenario, eight-role pipeline. The cause was structural: no gate ever drove the *running* system through its real production interface — every check ran below the surface, against functions and return values. The fork closes this with a **surface harness doctrine**: the roles that own live verification drive the running system through its actual surface, using a declared tool, and every surface carries a permanent idle baseline.

This is the reference verification loop's execute-and-observe layer (its Steps 5–7) made concrete: build the real thing, drive it through its surface, assert on what comes out.

**Surface tool table (in `engineering.prompt`).** Following the existing language-tool-table pattern, the constitution declares the harness tool per surface type: tmux/PTY for a TUI (`send-keys -l` for raw input at controlled timing, `capture-pane` for screen state over time), Playwright for web, an HTTP client for HTTP APIs, event-injection-at-ingress for headless services. Roles owning live verification — **QA** (both packs) and the **UX Engineer** (six-pack, ADR 0007) — identify the project's surface *from the codebase* and acquire the matching tool before their first harness run, exactly as they acquire language tools.

**No surface field in `project.prompt`.** Roles read the code to know the surface; an explicit declaration would be a meaningless placeholder until the project is customised. (The pre-reset summary table mentioned a `project.prompt` surface field — that was superseded by this decision; the real artifacts carry no such field.)

**Every surface carries a mandatory baseline scenario**, committed alongside the flow scenarios: TUI → idle stability (no input, consecutive captures identical, zero scrollback growth); web → idle page loads with no console errors; headless → a no-op event produces no state change. The baseline is what the tetris defects would have hit — they were *idle-state* failures invisible to any flow test, because flow tests only assert while the user is acting.

**QA verifies through the declared surface harness, not "the UI" (idea Q).** Upstream QA's "operate through the user interface only" was right in intent but mechanically silent — it let in-process function calls masquerade as UI verification. The fork replaces the phrase with "through the declared surface harness," and adds an auditable conversion rule: **every Expected bullet maps to a harness assertion, or is explicitly marked `NOT AUTOMATED — <reason>`.** This is the mechanism that makes the conversion-fidelity guard of ADR 0005 checkable rather than a matter of QA's word — a silently dropped bullet becomes a visible marker. Findings route back per ADR 0004.

## Considered options

- **Keep "through the UI only"** — rejected: no mechanical referent, so in-process calls and constant-checks wore the name of behavioral verification; this is exactly how the tetris defects slipped through.
- **Flow scenarios only, no idle baseline** — rejected: the defects were idle-state, which no flow scenario observes; the baseline is the part that actually closes the gap.
- **Declare the surface in `project.prompt`** — rejected: placeholder until customisation, and agents can read the surface from the code.

## Pending implementation

- Add the surface tool table + context-driven acquisition rule to `engineering.prompt` on `four-pack` and `six-pack`.
- Change QA's "through the UI only" to "through the declared surface harness" and add the Expected-bullet → assertion / `NOT AUTOMATED` rule in `QA.prompt` (both packs).
- Require the per-surface baseline scenario to be committed with every feature's flow scenarios.

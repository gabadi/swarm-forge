# Observation Harness and Dependency Fidelity Ladder

Working definition — 2026-06-10. Documentation format/home not yet decided; treat this file as the source of truth for this work until one is.

Inputs: the tetris escaped-defects incident (2026-06-09), analysis of `six-pack`/`four-pack` constitutions, StrongDM "Digital Twin Universe" docs, vercel-labs/emulate research.

---

## 1. Context: the incident that forced this

The tetris project (`gamaleds/tetris`, Go TUI) exists to exercise SwarmForge, not as a goal in itself. After three deliveries through the full six-pack pipeline — specifier → coder → ux-engineer → cleaner → architect → hardender → ux-engineer → QA → integrator, with mutation testing, CRAP ≤ 6, DRY, 168 unit + 61 acceptance + 19 property tests, all green — the user launched the game and found two defects within seconds:

1. **Screen blink** (shipped in delivery #1, survived three deliveries): `Frame.String()` wrote `\r\n` after every row including the last; with a frame exactly terminal-height tall, the final newline scrolled the whole screen one line every repaint (10 Hz). Verified empirically: tmux scrollback grew at exactly 10 lines/second.
2. **Runaway DAS** (delivery #3): raw-mode terminals deliver no key-release events. The DAS implementation armed a 167 ms timer per left/right press; after it fired, a goroutine moved the piece every 33 ms **forever** — stopped only by pressing a *different* key. One single keypress slammed the piece into the wall in ~250 ms. Verified empirically: one `ESC[D` byte sent to a PTY reproduced it.

### Why no gate caught them — the five findings

**F1. The spec predicted the bug; no rule forced acting on it.** The specifier's QA procedure (QA-MR-8) stated verbatim: *"On release, movement stops immediately."* That is exactly the behavior that shipped broken.

**F2. The code admitted the bug; the conflict was suppressed instead of escalated.** The shipped code contained: *"Key-up is not available in raw terminal reads; we detect release implicitly: any key other than the held direction cancels DAS."* That comment is the defect, described by its author. A "spec conflicts with platform reality" situation existed and was worked around silently. (Also: the DAS code was implemented by the **ux-engineer** — the role that then verified its own work.)

**F3. QA's end-to-end rule silently degraded.** QA prompt: *"Run the end-to-end QA suite through the user interface only; do not use an API into the project."* What was actually built: in-process Go tests calling `mrSession()` / `handleKey()` / `Render()` — internal APIs. The five-bullet timing procedure QA-MR-8 became `assert dasDelay == 167ms` — a constants check wearing the procedure's name. Nothing checks conversion fidelity.

**F4. Rules without a mechanical trigger don't execute.** The cleaner prompt already said *"Move behavior out of environmentally unsuitable modules into testable modules."* It never fired: boundary files appear in **no tool's worklist** (CRAP list, DRY list, mutation manifest, coverage), so no role ever opened `tui.go`. Pure timing logic (a DAS state machine) lived in the one file no tool touches — excluded from everything **by design** (engineering rules: "Only testable modules should participate in tools that run tests"). Dually, `Frame.String()` *was* in a testable module but its tests asserted `PlainRows()` (ANSI-stripped), so the only thing `String()` adds — escape codes and newline placement — was asserted by nothing.

**F5. Rigor was distributed by testability, not by risk.** Mutation/CRAP/DRY saturated the pure modules; zero verification existed at the seam where the program meets the user. Nobody — human or agent — ever ran the binary and observed it. The only role told to ("run the binary and observe the live experience" — ux-engineer) left no evidence, and nothing demands evidence.

### The one-sentence diagnosis

> SwarmForge verifies **artifacts about the system** (tests, mutation scores, specs) but has no gate that verifies **the running system through its real interface** — and the gap is surface-agnostic: the same hole exists for web (no browser ever loads the page), APIs (no request ever hits a running service), and platform services (no event ever flows through the deployed topology).

---

## 2. Decision overview

Two doctrine additions to the constitution, five concrete process changes, one validation strategy.

**Doctrine A — Observation Harness.** Every project must have a tool that drives the real, running system through the same interface its users use, and captures observable state for assertion.

**Doctrine B — Dependency Fidelity Ladder.** Everything the system depends on is explicitly placed on a four-tier ladder (real > emulated > stubbed), decided per dependency, with declared gaps.

---

## 3. Doctrine A: the Observation Harness

### Definition

A per-project tool (or tool set) able to: (a) start the system as it ships, (b) inject inputs through its production interface at controlled timing, (c) capture observable state over time, (d) support assertions on those captures. Harness scenarios are **committed code** — re-runnable by any role.

### Surface tool table (extends the existing language tool table pattern)

| Surface | Harness | Mechanism |
|---|---|---|
| TUI / terminal | tmux (or PTY driver) | `new-session` against the real binary; `send-keys -l` for raw bytes (timing-controlled); `capture-pane` for screen state; assertions on captures over time |
| Web UI | Playwright CLI | real browser against a running instance |
| HTTP API | HTTP client (hurl/curl-class) | real requests against a running instance — never in-process handlers |
| Headless service / platform component | event injection | real events at the system's ingress; observation at its egress and at dependency state (`twin_state`, §4) |

The project declares its surface(s) in `project.prompt`, exactly as it declares its language. Roles owning live verification (ux-engineer, QA) acquire the surface harness at startup, same as language tools.

### The two invariants

**I1 — The seam is always the wire, never the code.** Whatever is substituted or driven, the system under test communicates over the same protocol it uses in production: terminal bytes, HTTP, SQL, TCP. In-process fakes/mocks are unit-test machinery and never satisfy a harness obligation. *(This is the direct generalization of F3: `handleKey()` in-process instead of `ESC[D` over a PTY is what blinded every gate.)*

**I2 — Environment inputs are inputs.** Clock, OS input timing, randomness, network jitter — what cannot be containerized must be injectable through the same wire (e.g., bytes sent at controlled intervals). *(The DAS bug lived entirely in this category: OS key-repeat timing was an input nobody could synthesize, so nobody did.)*

---

## 4. Doctrine B: the Dependency Fidelity Ladder

### Boundary rule

**The system under verification is the deployment unit** — everything that ships when the swarm lands a PR. Inside: always real. Everything else is *environment*, provisioned at the highest fidelity that can run locally.

### The four tiers — discriminator questions asked in order

**Tier 0 — the system itself.** *Does it ship in this PR?* → Runs real, exactly as it ships (real binary / container / process). Never substituted, never shortcut. This is what the harness observes.

**Tier 1 — owned infrastructure.** *Can the production engine run locally?* → Run the real engine in a container. Postgres in Docker **is** Postgres; same for Redis, Kafka, RabbitMQ. Not emulators — the real dependency, locally provisioned. Only version pinning required.

**Tier 2 — emulated dependencies.** *Is a stateful, protocol-level emulation available (or buildable)?* → Use it, with a mandatory gap declaration. Tier 2 is defined by **mechanism** (stateful, protocol-faithful, cross-request semantics), not by author. Trust ranking within the tier:
1. vendor-official emulator (Firebase emulator, AWS-official)
2. established third-party (vercel-labs/emulate, LocalStack)
3. **swarm-built twin — last resort**, triggers the shared-blindspot rule (§4.1)

**Tier 3 — external domain.** Everything whose lifecycle the swarm does not own: third-party paid APIs (Stripe, email), **and other teams' services inside the same platform**. → Wire-level stub (WireMock/Prism-class) backed by a recorded or agreed contract. **Never called real in the verification loop** — unownable state and side effects make "real" flaky, not honest. Cross-domain truth belongs to contract testing / platform CI, not to swarm gates; consumer-driven contracts can ride on the same stubs.

### Requirements on every tier-2/3 dependency

1. **Machine-readable fidelity manifest** — each dependency is listed in `project.prompt` with: name, tier, implementation, declared gaps (tier 2: what the emulator doesn't implement; tier 3: contract reference + version). Machine-readable so the specifier and QA can programmatically refuse to write/accept scenarios that rest on a declared gap.
2. **State observability (`twin_state`)** — the dependency must expose post-interaction state for assertion ("the email is in the twin's outbox", "the S3 object exists"). The harness observes the SUT's surface **and** its effect on the environment.
3. **Seeded, reset state per scenario** — every harness scenario starts from declared seed state; no inter-scenario contamination, no ordering dependence.

### 4.1 The shared-blindspot rule (swarm-built twins)

*"If the same model builds the code AND the twin, both share the same misunderstandings — the twin passes scenarios because it has the same bugs as the product."* (StrongDM DTU docs; they list twin-fidelity validation as an unsolved problem.)

Rule: a swarm-built twin may **not** be authored by the role/context that wrote the SUT code, and must be validated against something external to the swarm: recorded real-API traffic samples or official-SDK conformance tests (the vercel-labs/emulate approach: run the vendor's real client library against the emulator).

### Honest limitation (recorded deliberately)

This strategy verifies *your system given the declared environment*. Defects hiding inside declared tier-2 gaps or behind tier-3 contract drift are **out of scope by design** — they belong to contract verification and staging. Twin fidelity is not solved; it is **declared and bounded**. Naming this boundary is what keeps the harness trustworthy rather than falsely reassuring.

---

## 5. The five process changes

| # | Change | Lands in | Justified by |
|---|---|---|---|
| C1 | **Surface tool table + harness acquisition rule** (§3). Project declares surface(s) + dependency manifest in `project.prompt`. | `constitution/engineering.prompt`, `constitution/project.prompt` (both `four-pack` and `six-pack` branches — installation instructions confirmed still inline there, not in a separate prompt; follow the existing language-table pattern) | F5, F3 |
| C2 | **QA conversion fidelity rule**: every "Expected" bullet of a QA procedure maps to a harness assertion, or is explicitly marked `NOT AUTOMATED — <reason>` and escalated. Asserting constants/config never substitutes for asserting behavior. QA's "through the UI only" becomes "through the declared surface harness". | `roles/QA.prompt` | F3 |
| C3 | **Platform-feasibility stop rule**: extend the existing "UX Intent vs Gherkin conflict → stop and report" to "spec vs platform capability conflict → stop and report". A workaround comment in code is the smell that this rule fired and was suppressed. | constitution (binds specifier, coder, ux-engineer) | F1, F2 |
| C4 | **Boundary logic detection**: the cleaner already runs `mutate4go --scan` for split decisions — extend the same scan to boundary files with a threshold (~15–20 mutation sites). Above threshold = logic, not adaptation → extract to a testable module before handoff. No new test types: extraction funnels hidden logic into the existing loops (mutation manifest, CRAP, coverage, unit TDD) automatically; the hardender's differential runs pick up new files with zero rule changes. Also: "tested only through a stripped/simplified view" counts as untested (the `PlainRows()` case). | `roles/cleaner.prompt`, `roles/architect.prompt` (adapter-boundary check) | F4 |
| C5 | **Evidence as code, checked twice**: the ux-engineer's verification deliverable is committed, re-runnable harness scenarios (not claims, not screenshots — agents can fabricate captures; only reproducibility counts). **Semantic check:** QA re-executes them independently. **Mechanical check:** the handoff format gains a required field (path to harness scenarios); missing field → handoff rejected by the delivery sequence, same as a missing commit hash. The scenarios double as the feature's permanent regression suite. | `roles/ux-engineer.prompt`, `roles/QA.prompt`, `constitution/workflow.prompt` (handoff format), possibly `notify-agent.sh` validation | F5, F2 |

Priority: C1 + C2 first (they would have caught both bugs and unblock C5). C3 + C4 are cheap prompt edits that ride along.

---

## 6. Validation strategy: escaped defects as process regression tests

A SwarmForge change is proven when re-running the pipeline on the bench project **retroactively catches the bug that escaped**. For this incident:

1. Build the TUI Observation Harness for tetris (tmux/PTY — formalizing the ad-hoc verification used to find both bugs; ~10 lines of shell per scenario).
2. Re-convert QA-MR-8/9 against it under C2 → the test **must fail against pre-fix commit `a0cd7ca`** and pass against the fixed tree. Likewise a screen-stability scenario (scrollback growth == 0) vs the blink.
3. Land the two pending tetris fixes (in the tetris working tree, uncommitted as of this writing: `pkg/tui/render.go` newline fix; `pkg/tui/tui.go` DAS machinery removal) plus the DAS spec revision — decide: OS-autorepeat as accepted behavior, or kitty keyboard protocol as a future delivery. Note `TestQA_MR8_DASConstantsMatchSpec` currently pins the constants.

General pattern going forward: every escaped defect produces (a) a harness scenario that reproduces it, (b) a process-change candidate, (c) verification that the change catches the original escape.

---

## 7. Rejected alternatives (with reasons)

- **Single "twin everything external" category (StrongDM DTU model)** — no real/emulate/stub decision rule; uses "mock" and "twin" interchangeably; loses the fidelity information that determines where bugs can still hide. Our tiers 0/1 (run real) have no analog there at all.
- **Calling real third-party or other-team services in the verification loop** — unownable state, side effects, availability; makes gates flaky rather than honest.
- **In-process fakes as harness machinery** — the in-process seam is precisely what blinded every gate (F3). Fakes stay in the unit loop.
- **"Vendor-official" as the tier-2 definition** — trust attribute, not mechanism; would wrongly exclude emulate/LocalStack-class tools.
- **vercel-labs/emulate as *the* tier-3 strategy** — 13 services is a coverage cliff (pre-1.0, single-vendor, no contract verification, gaps as README prose). It is the preferred tier-2 implementation where coverage exists; agent-friendly (`npx emulate`, no keys, no network). Generic wire stubs remain the universal fallback.
- **Evidence as screenshots/claims checked at handoff** — fabricable; only re-runnable scenarios independently re-executed count.
- **Honor-system rules without a mechanical trigger** — "run the binary and observe" and "move logic out of boundaries" both existed and both silently failed. Every new rule must name its tool, its worklist, and its checker.
- **Solving twin fidelity** — unsolvable in general (DTU docs concede it as open). We declare and bound gaps; what's out of bounds is explicitly routed to contract verification/staging.
- **Asserting configuration as a proxy for behavior** — `assert dasDelay == 167ms` is the canonical counterexample.
- **Treating the bench project (tetris) as the goal** — improvements land in this fork first; the bench validates them.

## 8. Adopted from external sources (provenance)

- **StrongDM DTU docs** (`melech/software-factory/docs/factory`): `twin_state` as a first-class observation type; per-scenario twin lifecycle/state reset as an explicit contract; the shared-blindspot rule and its mitigation (different model families + cross-reference real API samples); the economic argument that AI-built twins are now routine — which is exactly why the guardrail must exist.
- **vercel-labs/emulate**: tier 2 defined by mechanism, not author; official-SDK conformance testing as twin validation; proof that stateful protocol-level emulation (real OAuth flows, webhook delivery, cross-request state) is materially better than static stubs for multi-step agent scenarios.
- Both sources independently confirm invariants I1/I2; neither has machine-readable gap declaration — that discipline is this fork's addition.

---

## 9. Next session work plan

1. Draft prompt diffs against `six-pack` for C1–C5 (then port to `four-pack`); each diff annotated with its `F#`/section justification from this document.
2. Decide handoff-format change details for C5 (field name, validation point in the delivery sequence / `notify-agent.sh`).
3. Tetris bench work (§6): harness tool, QA-MR-8/9 re-conversion, regression validation against `a0cd7ca`, land the two pending fixes + DAS spec decision.
4. Consider: minimal-diff policy implications (ADR 0001) — these are permanent divergences from upstream; document them in ADR 0001's divergence list once implemented (that file keeps its ADR format).

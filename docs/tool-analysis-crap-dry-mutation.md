# Code Quality Tools: CRAP / DRY / Mutation

**Scope:** JavaScript/TypeScript, Python, Rust source targets
**Goal:** Cover all three tool families for all three stacks, matching Uncle Bob's Go/Clj/Java tools

---

## Status

| Stack | CRAP | DRY | Mutation |
|-------|------|-----|----------|
| **JS/TS** | `crap4js` v0.1.0 — **done** | `drywall` — **done** | `mutate4js` npm v0.1.0 — **done** (`gabadi/mutate4js`) |
| **Python** | `crap4py` v0.1.1 — **done** | `drywall` — **done** | `mutate4py` PyPI — **done** (`gabadi/mutate4py`) |
| **Rust** | `cargo-crap` — **reuse** | `drywall` — **done** | `mutate4rs` crate — **todo** |

---

## 1. What Exists Today

### crap4js v0.1.0
- **Install:** `npm install --save-dev @gabadi/crap4js`
- **Source:** `github.com/gabadi/crap4js` (private — install from the npm registry only)
- Branch coverage (BRDA) and `?.` CC exclusion are both implemented

### drywall v0.1.0
- **Install:** `cargo install --git https://github.com/gabadi/drywall --tag v0.1.0`
- **Source:** `github.com/gabadi/drywall`
- Single Rust binary covering JS/TS (OXC), Python (tree-sitter-python), Rust (syn)
- Implements Uncle Bob's AST subtree Jaccard algorithm
- Drop-in CLI compatible with dry4go

### crap4py v0.1.1
- **Install:** `pip install crap4py`
- **Source:** `github.com/gabadi/crap4py`
- Python source analysis via stdlib `ast` module
- Branch coverage from LCOV (pytest-cov / coverage.py)

### cargo-crap
- Reuse as-is (pre-1.0 but functional)
- Requires lcov.info from `cargo llvm-cov --lcov`

---

## 2. What to Build

### 2.1 crap4py — **done** (PyPI v0.1.1)

- **Install:** `pip install crap4py`
- **Source:** `github.com/gabadi/crap4py`
- Analyzes Python source using Python's own `ast` module
- Branch coverage via LCOV (pytest-cov / coverage.py with `branch = True`)
- Output matches crap4go column format — Function, Module, CC, Cov%, CRAP — sorted worst first

### 2.2 mutate4js — **done** (npm v0.1.0)

- **Distribution:** npm package (`npm install --save-dev mutate4js`)
- **Parser:** `@typescript-eslint/typescript-estree` (not OXC as originally planned)
- **Manifest comment style:** `// mutate4js-manifest: version=1`

```
mutate4js [flags] path/to/file
```

### 2.3 mutate4rs — Rust mutation (crate)

- **Distribution:** cargo crate (`cargo install mutate4rs`)
- **Parser:** `syn` (higher semantic fidelity for Rust source)
- **Manifest comment style:** `// mutate4rs-manifest: version=1`

```
mutate4rs [flags] path/to/file.rs
```

**Shared flags (mutate4js + mutate4rs + mutate4py):**

| Flag | Default | Description |
|------|---------|-------------|
| `--test-command` | (required) | Test command to run |
| `--since-last-run` | false | Differential: skip functions whose hash matches manifest |
| `--mutate-all` | false | Force full run, ignore manifest |
| `--reuse-coverage` | false | Skip coverage regeneration |
| `--lcov` | — | Path to pre-generated LCOV file |
| `--max-workers` | 1 | Parallel mutation workers |
| `--scan` | false | Count mutation sites only, no tests |
| `--verbose` | false | Log actions to stderr |

### 2.4 mutate4py — **done** (PyPI, `gabadi/mutate4py`)

Built with the swarm six-pack + `entire` (checkpoints →
`gabadi/mutate4py-entire`). The authoritative design lives in that repo's
`docs/spec.md` — a faithful `mutate4go` port with the user-facing contract
cross-checked against `unclebob/clj-mutate`. §3–§5 below are **superseded** by it.

```
mutate4py [flags] path/to/file.py
```

Locked `[PY]` divergences (see repo spec for full rationale):

- **Serial only — `--max-workers` removed.** *(Superseded in implementation:
  `--max-workers` and a worker pool shipped; see the repo spec.)*
- **Coverage acquired explicitly** via `--lcov` / `--cov-cmd` / `--reuse-coverage`
  (no universal Go `-coverprofile` equivalent); reads LCOV from coverage.py.
- **Manifest hash = `ast.dump()`** (structural), not whitespace-collapse —
  Python's indentation is significant.
- **Operators localized:** core set + `and`/`or` + `True`/`False` + comparison
  negation flips `==`/`!=`, `is`/`is not`, `in`/`not in`.
- **`--test-command` defaults to `pytest`.**
- Substrate: stdlib `ast`, hatchling/PyPI, `uvx` (mirrors `crap4py`).

Note: the `mutate4js` grilling also reversed one decision **upstream** — the JS
port should add `===`/`!==` (the dominant idiomatic equality operator), by the same
localize-per-language principle.

---

## 3. Key Decisions

### Why port mutation instead of reusing StrykerJS / mutmut / cargo-mutants

All three existing tools lack the property that makes mutate4go useful in practice:
an embedded-in-source manifest.

| Property | mutate4go | StrykerJS | mutmut | cargo-mutants |
|----------|-----------|-----------|--------|---------------|
| Manifest stored in source file | Yes | No | No | No |
| Survives repo clone | Yes | No | No | No |
| Team-shared automatically | Yes | No | No | No |
| Zero CI setup for incremental | Yes | No | No | No |
| Incremental granularity | per-function hash | per-mutant position | per-function hash | line (external diff) |

The manifest is embedded as comments in the source file footer, committed with the code.
Any developer who pulls the repo gets differential reruns automatically. StrykerJS's
incremental JSON and mutmut's SQLite cache are external artifacts that each require
explicit CI cache configuration and provide nothing to developers working locally.

### Why crap4py is not a port of crap4go

crap4go analyzes **Go** source. crap4py analyzes **Python** source. They implement the
same CRAP formula but are completely separate tools using their language's native AST.
There is no Python port of crap4go to reuse — it does not exist.

### Why mutate4js, mutate4rs, and mutate4py are separate tools

Each tool is distributed through its language's native registry (npm / crates.io / PyPI),
matching the pattern established by crap4js, cargo-crap, and crap4py. A JS developer
should be able to `npm install mutate4js` without cargo; a Rust developer `cargo install mutate4rs`
without Node. Implementation may share a common Rust library (OXC + syn), but the
distribution is language-native.

---

## 4. Mutation Algorithm

Same for all three ports. Matches mutate4go's implementation.

**Per run:**
1. Parse source file → walk functions → normalize each (identifiers → `_ID`, literals → `_LIT`) → hash (FNV-1a)
2. Read embedded manifest from file footer; skip functions whose hash matches
3. For changed functions: read LCOV → for each covered mutation site → apply operator → run test command → restore
4. Write updated manifest to file footer

**Operator set** (Uncle Bob's spec):

| Category | Mutations |
|----------|-----------|
| Arithmetic | `+` ↔ `-`, `*` → `/` |
| Comparison | `>` ↔ `>=`, `<` ↔ `<=` |
| Equality | `==` ↔ `!=` |
| Boolean | `true` ↔ `false` |
| Logical | `&&` ↔ `||` |
| Constant | `0` ↔ `1` (inline, in expressions) |
| Unary | remove `-a` → `a`, remove `!a` → `a` |
| Null | replace return value with `null` / `None` |

**Manifest format** (identical across all three, language-native comments):

```python
# mutate4py-manifest: version=1
# fn:compute_score hash=a3f9c1d2 lines=5-25 tested=2026-06-21
# fn:validate_input hash=b7e2a4f1 lines=30-48 tested=2026-06-21
```

```typescript
// mutate4js-manifest: version=1
// fn:computeScore hash=a3f9c1d2 lines=5-25 tested=2026-06-21
```

---

## 5. Open Questions

- Whether dry4go's 0.82 Jaccard threshold needs calibration for JS/Python codebases
- Whether `syn` or `tree-sitter-rust` is the better choice for mutate4rs normalization
  (`syn` has higher semantic fidelity; `tree-sitter-rust` is consistent with the other parsers in drywall)
- Whether cargo-crap's pre-1.0 status is a blocker or acceptable for internal use

---

## Appendix A — LCOV Format Reference

LCOV tracefile format is produced by Jest, Vitest, c8, nyc, pytest-cov, coverage.py,
cargo-llvm-cov, and cargo-tarpaulin.

| Record | Syntax | Meaning |
|--------|--------|---------|
| `SF` | `SF:<path>` | Opens a source file section |
| `FN` | `FN:<start>[,<end>],<name>` | Function declaration |
| `FNDA` | `FNDA:<count>,<name>` | Function execution count |
| `BRDA` | `BRDA:<line>,<block>,<branch>,<taken>` | Branch edge (`taken='-'` means unreachable) |
| `BRF` | `BRF:<count>` | Total branch records |
| `BRH` | `BRH:<count>` | Branch records with taken > 0 |
| `DA` | `DA:<line>,<count>` | Line execution count |
| `end_of_record` | `end_of_record` | Closes a source file section |

CRAP uses branch coverage: `cov(m) = BRH_in_function / BRF_in_function × 100`.
Dead branches (`taken='-'`) are excluded from both numerator and denominator.

**coverage.py requirement:** add `branch = True` to `.coveragerc` to emit BRDA records.

---

## Appendix B — Uncle Bob Reference CLIs

### crap4go
```
crap4go [--test-command <cmd>] [--max-workers <n>] [path-fragment ...]
```
Deletes stale coverage → runs test command → parses LCOV + AST → prints CRAP per function, sorted worst first.

### dry4go
```
dry4go [--threshold 0.82] [--min-lines 4] [--min-nodes 20] [--format text|json] [path ...]
```

### mutate4go
```
mutate4go [--since-last-run] [--mutate-all] [--scan] [--test-command <cmd>] [--max-workers 1] path/to/file.go
```
Embedded manifest in source file footer. Differential by default when manifest exists.

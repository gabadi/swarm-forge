# Code Quality Tool Analysis: CRAP / DRY / Mutation

**Status:** Research complete — decision pending  
**Scope:** JavaScript/TypeScript, Python, Rust source targets  
**Goal:** Determine what to reuse, what to build, and in what language

---

## 1. Background

The engineering constitution (`swarmforge/constitution/articles/engineering.prompt`) mandates
procuring CRAP, mutation, and DRY tools from Uncle Bob's repositories on startup.
Those repositories (`github.com/unclebob/{crap,dry,mutate}4{go,clj,java}`) only cover
Go, Clojure, and Java. This document defines what to do for the remaining stacks.

---

## 2. Tool Family Definitions

### 2.1 CRAP (Change Risk Anti-Pattern)

Measures per-function risk as a function of complexity and test coverage.

**Formula:** `CRAP(m) = CC(m)² × (1 - cov(m)/100)³ + CC(m)`

Where:
- `CC(m)` = cyclomatic complexity of function `m` (decision points + 1)
- `cov(m)` = percentage of the function's branches (or lines) covered by tests

**Decision points counted:** `if`, `else if`, ternary (`?:`), `&&`, `||`, `??`,
`for`, `for…in`, `for…of`, `while`, `do…while`, `catch`, each `switch case`.

**Interpretation:**
- Score 1 = perfect (CC=1, 100% coverage)
- Score ≥ 30 = conventionally "crappy" (high complexity AND low coverage)
- A function with CC=10 and 0% coverage scores 1010; same function at 100% scores 10

### 2.2 DRY (Don't Repeat Yourself)

Detects structurally duplicated code using AST subtree hashing and Jaccard similarity.
Catches semantic duplication (same logic, different variable names), not just copy-paste.

**Uncle Bob's algorithm:**
1. Parse source file to AST
2. Walk every node, collecting all subtrees at every nesting depth
3. Normalize each subtree: replace all identifier names and literal values with
   `_ID` and `_LIT` (operators, control-flow keywords, and structure are preserved)
4. Serialize and hash each normalized subtree
5. Build inverted index: hash → list of (file, function, subtree) tuples
6. For any two functions sharing at least one hash, compute Jaccard similarity:
   `|shared hashes| / |union of hashes|`
7. Report pairs above the similarity threshold (default 0.82)

**Qualification gates:** functions must have ≥ 4 source lines AND ≥ 20 normalized AST nodes.
Below this threshold the signal-to-noise ratio collapses.

**Key property:** Two functions that do the same thing with completely different variable
names will match. Two functions with an identical copy-paste block surrounded by different
code will not match at the function level (only the block would match if it were extracted).

### 2.3 Mutation Testing

Verifies test suite quality by injecting deliberate faults into source code and checking
whether tests detect them. A mutant that survives (tests still pass) indicates a gap in
test assertions.

**Uncle Bob's operator set:**

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

**Key innovations in Uncle Bob's implementation:**
- **Embedded manifest:** function hashes stored in source file footer comments;
  enables differential reruns — only functions changed since last run are retested
- **Coverage gating:** only lines covered by at least one test are mutated;
  avoids wasting time on dead code
- **Parallel workers:** isolated copies per worker for concurrent mutation

---

## 3. Uncle Bob Reference Tool Interfaces

### 3.1 crap4go CLI

```
crap4go [--test-command <cmd>] [--max-workers <n>] [path-fragment ...]
```

| Flag | Default | Description |
|------|---------|-------------|
| `--test-command` | `go test ./... -coverprofile=target/coverage/coverage.out` | Coverage command; tool appends `-coverprofile` unless `{coverprofile}` placeholder present |
| `--max-workers` | half of logical CPUs | Parallel source-file analysis workers |

Positional arguments: path fragments — only files whose path contains a fragment are included.
No arguments = all files.

**Behavior:** deletes stale coverage → runs test command → parses coverage + AST →
computes CRAP per function.

**Skips:** `_test.go`, `target/`, `vendor/`, `.git/`

**stdout:**
```
CRAP Report
===========
Function                       Package                               CC   Cov%     CRAP
-------------------------------------------------------------------------------------
Widget.Run                     widget                                12   45.0%    130.2
simple                         widget                                 1  100.0%      1.0
```
Sort: descending by CRAP score (worst first). N/A last.

**Coverage file:** Go coverage profile (`target/coverage/coverage.out`)

### 3.2 dry4go CLI

```
dry4go [options] [file-or-directory ...]
```

| Flag | Default | Description |
|------|---------|-------------|
| `--threshold` | `0.82` | Minimum Jaccard similarity to report |
| `--min-lines` | `4` | Minimum source lines in a candidate function |
| `--min-nodes` | `20` | Minimum normalized AST nodes |
| `--format` | `text` | `text` or `json` |
| `--json` | — | Alias for `--format json` |

Directories are recursed; `.git`, `vendor`, `target` excluded.

**Text output:**
```
DUPLICATE score=0.89
  internal/billing/invoice.go:12-25
  internal/billing/receipt.go:30-44
```

**JSON output:**
```json
{
  "candidates": [
    {
      "score": 0.8909090909090909,
      "left":  {"file": "internal/billing/invoice.go", "start_line": 12, "end_line": 25},
      "right": {"file": "internal/billing/receipt.go", "start_line": 30, "end_line": 44},
      "left_nodes": 88,
      "right_nodes": 91
    }
  ]
}
```

### 3.3 mutate4go CLI

```
mutate4go [flags] path/to/file.go
```

One source file per invocation.

| Flag | Default | Description |
|------|---------|-------------|
| `--scan` | false | Count mutation sites vs. manifest only; no tests |
| `--update-manifest` | false | Rewrite footer manifest without running mutations |
| `--lines <n,n,...>` | — | Restrict to specific line numbers |
| `--since-last-run` | false | Differential: test only changed functions |
| `--mutate-all` | false | Force full mutation ignoring manifest |
| `--reuse-coverage` | false | Skip coverage regeneration |
| `--mutation-warning` | 50 | Warn if mutation count exceeds threshold |
| `--timeout-factor` | — | Multiplier for per-mutation test timeout |
| `--test-command` | `go test ./...` | Override test command |
| `--max-workers` | 1 | Parallel mutation workers |
| `--verbose` | false | Log actions to stderr |

**Behavior:**
1. Generate coverage → run baseline tests (establish timeout)
2. For each covered mutation site: apply → run tests → restore → record
3. Default to differential mode if footer manifest exists
4. Write updated manifest to end of source file

**Manifest format:** embedded in source file footer comments; contains last-test-date,
per-function ID, line span, normalized-source hash.

---

## 4. Coverage Data Interface — LCOV Format

All CRAP implementations (existing and proposed) consume LCOV tracefile format.
This is the universal coverage interchange format produced by Jest, Vitest, c8, nyc,
Istanbul, pytest-cov, coverage.py, cargo-llvm-cov, and cargo-tarpaulin.

### 4.1 Record Types

| Record | Syntax | Meaning |
|--------|--------|---------|
| `TN` | `TN:<test name>` | Test name (optional; may be empty) |
| `SF` | `SF:<path>` | Opens a source file section |
| `FN` | `FN:<start>[,<end>],<name>` | Function declaration (end_line optional) |
| `FNDA` | `FNDA:<count>,<name>` | Function execution count |
| `FNF` | `FNF:<count>` | Total functions found |
| `FNH` | `FNH:<count>` | Functions with count > 0 |
| `BRDA` | `BRDA:<line>,[e]<block>,<branch>,<taken>` | Branch edge data |
| `BRF` | `BRF:<count>` | Total branch records |
| `BRH` | `BRH:<count>` | Branch records with taken > 0 |
| `DA` | `DA:<line>,<count>[,<checksum>]` | Line execution count |
| `LH` | `LH:<count>` | Lines with count > 0 |
| `LF` | `LF:<count>` | Total lines found |
| `end_of_record` | `end_of_record` | Closes a source file section |

### 4.2 BRDA Field Detail

```
BRDA:<line_number>,[e]<block>,<branch>,<taken>
```
- `line_number`: 1-based line of the branching statement
- `e` prefix (LCOV 2.x): exception-handling branch
- `block`: integer from 0; groups branches of the same conditional
- `branch`: edge index (0 = false/left path, 1 = true/right path for a simple `if`)
- `taken`: `-` (never evaluated / dead code) OR integer execution count

**Critical distinction:** `taken=0` means the branch was evaluated but never taken.
`taken=-` means the branch was never reached at all.

### 4.3 Line vs Branch Coverage in CRAP

The formula requires `cov(m)` — "how much of function m is tested." There are two interpretations:

**Line coverage (DA records):**
- A line with `count > 0` is "covered" even if only one side of its branch was tested
- Can overstate coverage significantly on functions with compound conditionals
- This is what **crap4js currently uses** (reads only `DA:` records)

**Branch coverage (BRDA records):**
- Counts each outgoing edge of each conditional independently
- `cov(m) = BRH_in_function / BRF_in_function × 100`
- More accurate to Uncle Bob's intent (he measures decision coverage)
- This is what the **proposed Python implementation should use**

### 4.4 Minimal Valid Example

```
TN:example
SF:/project/src/foo.py
FN:5,25,compute_score
FNDA:3,compute_score
FNF:1
FNH:1
BRDA:8,0,0,2
BRDA:8,0,1,1
BRDA:15,0,0,-
BRDA:15,0,1,3
BRF:4
BRH:3
DA:5,1
DA:6,3
DA:8,3
DA:9,2
DA:15,3
LH:5
LF:5
end_of_record
```

---

## 5. Decision Matrix by Stack

### 5.1 Mutation Testing

| Stack | Decision | Tool | Rationale |
|-------|----------|------|-----------|
| JS/TS | **Reuse** | StrykerJS | Mature, AST-based, coverage-gated per-test, mutation switching (single suite run) |
| Python | **Reuse** | mutmut | Mature, widely adopted, `--use-coverage` flag for coverage gating |
| Rust | **Reuse** | cargo-mutants | Active, `--in-diff` for PR-scoped runs, most operator categories covered |

**Rationale shared across all stacks:** The bottleneck is always test execution time.
A Rust reimplementation of the harness cannot make tests run faster — it would only
be orchestrating the same subprocesses. The existing tools are the right level of abstraction.

**Known gap — cargo-mutants vs Uncle Bob spec:**
- Inline constant swapping (`0↔1` inside expressions) is not implemented;
  cargo-mutants replaces entire function bodies with type defaults instead
- No coverage gating (all code is mutated regardless of coverage)
- Differential runs work via `--in-diff` / `--git-base` (different mechanism, same outcome)

### 5.2 CRAP

| Stack | Decision | Tool | Rationale |
|-------|----------|------|-----------|
| JS/TS | **Reuse + patch** | crap4js | Correct formula, lean (1,732 LOC), two known gaps (see below) |
| Python | **Write** | ~200-line Python script | Nothing exists; Python's own `ast` module is the right parser |
| Rust | **Reuse** | cargo-crap | Correct formula, reads lcov.info from llvm-cov/tarpaulin; pre-1.0 but functional |

**Known gaps in crap4js:**

1. **Line coverage instead of branch coverage** — reads `DA:` records only;
   ignores `BRDA:` records. A function with `if (a && b)` where only the
   `false` short-circuit path is tested shows as "covered". This understates CRAP
   on functions with compound conditionals. Fix: extend `coverage.ts` to parse
   `BRDA:` records and compute `BRH/BRF` per function line range.

2. **Optional chaining `?.` inflates CC** — every `user?.profile?.name` adds +1 to
   cyclomatic complexity per `?.`. Uncle Bob's spec (written for Go/Java/Clojure) has
   no such operator. Modern TypeScript code using `?.` for defensive access gets
   artificially high CC scores on simple property accessor chains.
   Fix: remove `MemberExpression`/`CallExpression` with `optional=true` from
   `DECISION_PREDICATES` in `complexity.ts:594-601`.

**Known gap in cargo-crap:**
- Pre-1.0 (v0.2.x); no historical trending, no per-PR delta, no IDE integration
- Requires `lcov.info` as intermediate; no native `llvm-cov` JSON support

### 5.3 DRY

| Stack | Decision | Tool | Rationale |
|-------|----------|------|-----------|
| JS/TS | **Write new** | Rust binary (see §6) | No AST-subtree-Jaccard tool exists; jscpd v5 is token-sequence only |
| Python | **Write new** | Rust binary (see §6) | Nothing exists |
| Rust | **Write new** | Rust binary (see §6) | cargo-dupes is function-level only, 4 stars, pre-production |

**Why not jscpd v5 for JS/TS?**
jscpd v5 (Rust, 5.1k stars, 150+ languages) is production-ready and catches copy-paste
duplication effectively. It uses tokenization + Rabin-Karp rolling hash over token
sequences. However it detects a different class of duplicates than Uncle Bob's algorithm:

| Scenario | jscpd v5 | Uncle Bob DRY |
|----------|----------|---------------|
| Copy-paste block (identical variable names) | Detects | Detects |
| Same logic, different variable names | Misses | **Detects** |
| Partial block match above threshold | Detects | May miss (function-level Jaccard) |

For a monorepo with multiple services, the Uncle Bob variant catches cases where
two teams independently implemented the same logic with different names — jscpd would not.
These are complementary tools; the decision to use Uncle Bob's algorithm is a deliberate
choice, not a gap in jscpd.

---

## 6. Proposed New Tool: DRY Rust Binary

### 6.1 Scope

A single Rust binary implementing Uncle Bob's DRY algorithm for JS/TS, Python, and Rust
source targets. One binary, one CLI, one output format.

### 6.2 AST Parsers

| Target | Parser | Rationale |
|--------|--------|-----------|
| JS/TypeScript | OXC (`oxc_parser` crate) | 21.6k stars, 3-5x faster than alternatives, spec-compliant, semantic enrichment (scope/binding) |
| Python | `tree-sitter-python` | Standard; Python's own `ast` module has better fidelity but requires CPython subprocess |
| Rust | `syn` crate | The canonical Rust AST parser; better semantic fidelity than tree-sitter-rust for Rust targets |

### 6.3 Algorithm (per target language)

1. Walk all source files; for each function/method/closure:
   a. Parse to language-native AST
   b. Collect all subtrees at every nesting depth
   c. Normalize each subtree: replace identifiers → `_ID`, literals → `_LIT`
   d. Hash each normalized subtree (FNV-1a or xxHash — fast, collision-resistant)
   e. Record `(file, fn_name, start_line, end_line, set<hash>)` per function
2. Build inverted index: `hash → Vec<FunctionRef>`
3. Generate candidate pairs: any two functions sharing ≥ 1 hash
4. For each candidate pair: compute Jaccard `|A ∩ B| / |A ∪ B|`
5. Report pairs with Jaccard ≥ threshold (default 0.82), where both functions
   pass the qualification gates (≥ 4 lines, ≥ 20 AST nodes)

### 6.4 Proposed CLI

```
dry [options] [path ...]
```

| Flag | Default | Description |
|------|---------|-------------|
| `--threshold` | `0.82` | Minimum Jaccard similarity to report |
| `--min-lines` | `4` | Minimum source lines to qualify |
| `--min-nodes` | `20` | Minimum normalized AST nodes to qualify |
| `--lang` | auto-detect | `js`, `ts`, `py`, `rs` — force language |
| `--format` | `text` | `text` or `json` |
| `--exclude` | — | Glob patterns to exclude |

Output format mirrors dry4go exactly (text and JSON) for drop-in compatibility.

### 6.5 Distribution

- Static binary (no runtime dependency) via `cargo build --release`
- Can be compiled to WASM via `wasm-pack` for npm distribution if needed
- Single binary covers all three target languages

### 6.6 Scaling (validated)

At the worst-case Python monorepo service (scoring: 491 files, ~684 functions, ~350
qualifying after gates): ~61,000 pairs, ~6 million hash comparisons — runs in under
1 second in Python; Rust will be significantly faster.
For JS monorepos with ~9,430 production files, the qualification gates reduce the
candidate set substantially; the inverted index further eliminates non-pairs cheaply.
No MinHash, LSH, or approximation needed at these scales.

---

## 7. Existing Tool Interfaces (for integration)

### 7.1 StrykerJS (JS/TS Mutation)

**Config file:** `stryker.config.mjs`

```js
export default {
  testRunner: 'jest',           // 'jest' | 'karma' | 'mocha' | 'command'
  coverageAnalysis: 'perTest',  // 'off' | 'all' | 'perTest'
  thresholds: {
    high: 80,                   // green above this
    low: 60,                    // yellow between low and high; red below low
    break: null,                // exit 1 if score falls below; null = never fail
  },
  mutate: ['src/**/*.ts'],
  excludedMutations: [],        // mutator names or category names
};
```

`coverageAnalysis: 'perTest'` is the correct setting — it gates each mutant to only
the tests that cover its line, equivalent to Uncle Bob's coverage-gated approach.

**Key mutator categories:** ArithmeticOperator, EqualityOperator, LogicalOperator,
BooleanLiteral, BlockStatement, ConditionalExpression, UnaryOperator, UpdateOperator,
OptionalChaining, StringLiteral, ArrayDeclaration.

### 7.2 mutmut (Python Mutation)

**Run:**
```
mutmut run [--use-coverage] [--paths-to-mutate src/] [--disable-mutation-types <types>]
```

**Mutation types available:** `operator`, `keyword`, `number`, `name`, `string`,
`fstring`, `argument`, `or_test`, `and_test`, `lambdef`, `expr_stmt`, `decorator`,
`annassign`

**Cache:** `.mutmut-cache` (SQLite, project root) — delete to reset

**Coverage gating:** `--use-coverage` flag reads coverage.py data; restricts mutations
to covered lines (equivalent to Uncle Bob's coverage gating)

**Differential runs:** `--use-patch-file <patch>` — mutate only lines in the patch

**Results:**
```
mutmut results          # print all results
mutmut result-ids survived   # list surviving mutant IDs
mutmut show <id>        # show diff for a specific mutant
```

**Exit codes:** 0 = all killed, 1 = survivors exist or fatal error

### 7.3 cargo-mutants (Rust Mutation)

**Key flags:**
```
cargo mutants [--in-diff <patch>] [--git-base <branch>] [--jobs <n>]
```

- `--in-diff <file>`: mutate only lines present in a unified diff
- `--git-base <branch>`: auto-generate diff from `git diff <branch>..HEAD`
- `--jobs <n>`: parallel workers

**Operator gaps vs Uncle Bob:** inline constant swapping (`0↔1`) not supported;
no coverage gating.

### 7.4 cargo-crap (Rust CRAP)

**Workflow:**
```
cargo llvm-cov --lcov --output-path lcov.info
cargo crap --lcov lcov.info
```

Also accepts tarpaulin output. Does not natively read `llvm-cov` JSON.

---

## 8. Open Questions

1. **Should crap4js be patched or left as-is?**
   The two gaps (line-vs-branch coverage, `?.` CC inflation) affect score accuracy.
   Patching is low-effort (~50 LOC changes). Decision: patch or accept the deviation?

2. **Should jscpd v5 be used alongside the proposed DRY binary?**
   They catch different things (copy-paste vs semantic duplication). Running both adds
   signal but also adds tooling surface area. Decision: one or both?

3. **Should the Python CRAP script use branch or line coverage?**
   Branch coverage is more accurate to Uncle Bob's intent but requires lcov to emit
   `BRDA:` records — pytest-cov does this by default; coverage.py does too with
   `branch = True` in `.coveragerc`. This is a one-time config addition, low risk.

4. **What is the output format / threshold for the DRY binary?**
   dry4go's threshold of 0.82 was tuned for Go. JS and Python have different idiom
   frequencies — the threshold may need calibration on real codebases.

5. **Should cargo-mutants' missing inline constant swapping be compensated?**
   It can be supplemented by a custom mutant configuration. Is the gap material?

6. **Where do the tools live?**
   - Fork and patch crap4js in the addi org? Or submit upstream?
   - Is the DRY Rust binary a new repo in the org? Which team owns it?

7. **CI integration strategy:**
   - Run on every commit? Every PR? Only on changed files?
   - What are the thresholds that block merge vs warn only?
   - Who owns the baseline — per-repo or org-wide?

---

## 9. Knowns

- crap4js exists at `/Users/gabadi/workspace/addi/crap4js` — audited, correct formula,
  production-quality, two patchable gaps
- Uncle Bob's DRY algorithm is O(n²) over qualifying fragments; at all measured repo
  scales (worst case: ~350 fragments), brute-force Jaccard runs in under 1 second
- LCOV is the universal coverage interchange format — all major test runners for
  JS/TS, Python, and Rust produce it
- Mutation testing's bottleneck is always test execution time; the harness language
  is irrelevant to performance
- Rust's OXC parser (21.6k stars, v1.70.0) is production-grade for JS/TS AST work
  and WASM-distributable
- Go tree-sitter bindings require CGO, breaking the zero-dependency binary story

## 10. Unknowns

- Whether the `?.` CC inflation in crap4js is material in practice on the JS monorepo
  (depends on how heavily optional chaining is used)
- Whether dry4go's 0.82 Jaccard threshold is appropriate for JS/Python codebases
- Whether `syn` (Rust AST) or `tree-sitter-rust` is the better choice for DRY
  analysis of Rust source (syn has higher fidelity but is Rust-only; tree-sitter-rust
  is consistent with the other language parsers)
- Actual build time of the proposed DRY Rust binary and whether WASM compilation
  is needed or if a native binary suffices for all CI environments
- Whether cargo-crap's pre-1.0 status is a blocker or acceptable for internal use

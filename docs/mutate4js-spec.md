# mutate4js — faithful port spec

Supersedes §2.2 and §4 of `tool-analysis-crap-dry-mutation.md` for the JS/TS
mutation tool. Authored by reading the actual `github.com/unclebob/mutate4go`
source (commit at HEAD, June 2026), not the plan's summary — which contained
several fabrications (catalogued in §9).

Each item is tagged:

- **[PORT]** — reproduce mutate4go's behavior exactly.
- **[JS]** — deviation forced by the JS/TS ecosystem, with the reason.

---

## 1. Substrate & distribution **[JS]**

mutate4go is a Go binary. mutate4js cannot be.

- **Language:** TypeScript. **Parser:** `@typescript-eslint/typescript-estree`
  (same parser as the JS sibling crap4js; full TS-syntax fidelity and exact
  source offsets for byte-precise splice/restore).
- **Toolchain:** Bun — `bun install`, `bun test`, run `src/cli.ts` directly (no
  build step). No tsup/pnpm/vitest.
- **Distribution:** published to the **npm registry** (Bun has no separate
  registry), installable by either `bun add -d mutate4js` or `npm i -D mutate4js`.
- **Reason:** a mutation tool is a per-project dev-dependency that runs in the
  project's own JS toolchain; a Rust/Go binary buys nothing because the per-mutant
  cost is the language-native test run, not the parse. (Full rationale: grilling
  Q1–Q2.)

---

## 2. CLI surface

Mutate-test one file at a time: `mutate4js path/to/file.ts [options]`

| Flag | mutate4go | mutate4js | Tag |
|------|-----------|-----------|-----|
| `--scan` | count sites, no coverage/tests | same | [PORT] |
| `--update-manifest` | rewrite footer manifest only | same | [PORT] |
| `--lines L1,L2,...` | only these source lines | same | [PORT] |
| `--since-last-run` | only changed functions | same | [PORT] |
| `--mutate-all` | all covered sites despite manifest | same | [PORT] |
| `--mutation-warning N` | warn when sites > N (default 50) | same | [PORT] |
| `--timeout-factor N` | mutant timeout = N × baseline (default 10) | same | [PORT] |
| `--max-workers N` | N isolated parallel workers | same | [PORT] |
| `--verbose` | log actions to stderr | same | [PORT] |
| `--help` | usage and exit | same | [PORT] |
| `--test-command CMD` | default `go test ./...` | **required**, no default | [JS] |
| `--cov-cmd CMD` | — (Go appends `-coverprofile`) | command that emits LCOV | [JS] |
| `--lcov PATH` | — (fixed `target/coverage/coverage.out`) | path to LCOV file | [JS] |
| `--reuse-coverage` | reuse coverprofile on disk | reuse LCOV on disk | [PORT]/[JS] |

**[JS] reasons:**

- `--test-command` has no sensible JS default (no universal `go test ./...`
  equivalent), so it is required.
- mutate4go gets coverage by appending `-coverprofile=...` to the test command
  (`coverageCommand()` in runner.go). **No universal JS flag does this**, so
  coverage acquisition is split out into `--cov-cmd` (run once, must emit LCOV),
  `--lcov PATH` (supply pre-generated), and `--reuse-coverage`. This is the one
  structural divergence in the command model. (Grilling Q3.)

**[PORT] mutual-exclusion rules** (from `cli.go`, reproduce exactly):
- `--scan` and `--update-manifest` are mutually exclusive and cannot combine
  with any execution option (`--lines`, `--since-last-run`, `--mutate-all`,
  `--timeout-factor`, `--test-command`, `--max-workers`).
- `--since-last-run`, `--mutate-all`, `--lines` are pairwise exclusive.
- Numeric flags reject non-positive / non-integer values.
- Missing source file → usage error.

---

## 3. Mutation operators **[PORT]** (plan was wrong)

Exact set from `mutations.go::binaryMutant` / `addLiteralMutation` / `boolMutant`:

| Category | Mutations |
|----------|-----------|
| Arithmetic | `+` → `-`, `-` → `+`, `*` → `/` |
| Comparison | `>` → `>=`, `>=` → `>`, `<` → `<=`, `<=` → `<` |
| Equality | `==` → `!=`, `!=` → `==` |
| Logical | `&&` → `\|\|`, `\|\|` → `&&` |
| Boolean | `true` → `false`, `false` → `true` |
| Constant | integer `0` → `1`, `1` → `0` (no other literals) |

- **No `/` → `*`** (only `*` → `/`). [PORT]
- **The plan's "Unary (remove `-a`/`!a`)" and "Null (replace return with
  null/None)" categories DO NOT EXIST in mutate4go.** Drop them. [PORT]
- One mutant per site; exactly one operator/literal per site.
- **[JS] mapping notes:** JS `==`/`!=` map directly; we do **not** add
  `===`/`!==` (mutate4go has no analog — keep the ported set, revisit only if
  field use demands). Numeric literal `0`/`1` only; strings, floats, BigInt not
  mutated. Apply `&&`/`||` on JS logical operators as-is.

---

## 4. Site discovery & function attribution

- **[PORT]** Walk the whole file's AST; every operator/boolean/`0`/`1` literal is
  a site. Sort sites by (line, column); assign a stable `Index`.
- **[PORT]** Each site is attributed to the enclosing function by **line range**
  (`functionIDAtLine`); sites outside any function get an empty FunctionID and
  are still mutated (module-level code is NOT skipped — corrects grilling Q4's
  "skip module-level" assumption).
- **[JS] function unit definition.** Go has only top-level `FuncDecl` (functions
  + methods). JS equivalent for the manifest unit:
  - top-level `function foo()` → `func/foo`
  - function/arrow bound to a name (`const foo = () => …`) → `func/foo`
  - class method → `func/Class.method`
  - nested anonymous arrows/callbacks are **not** separate units; their sites are
    attributed to the enclosing named unit by line range (matches
    `functionIDAtLine`). (Grilling Q4.)
- **[PORT]** `Apply` = string splice by byte offset
  (`content[:start] + mutant + content[end:]`); restore = rewrite original.

---

## 5. Manifest **[PORT]** (plan was entirely wrong)

**Real format (from `manifest.go`):** a single JSON object embedded in the file
footer between markers:

```
// mutate4js-manifest-begin
// {"version":1,"tested_at":"2026-06-24T...","module_hash":"<sha256>","functions":[{"id":"func/foo","name":"foo","line":5,"end_line":25,"hash":"<sha256>"}]}
// mutate4js-manifest-end
```

- **Hash = SHA-256** of the value (plan said FNV-1a — wrong).
- **Normalization = whitespace collapse only**: `text.split(/\s+/).join(" ")`
  (Go: `strings.Join(strings.Fields(text)," ")`). The plan's
  "identifiers→`_ID`, literals→`_LIT`" is **fiction**. Consequence: a manifest
  unit's hash changes on *any* textual edit (including renames and number
  changes); only reformatting is ignored. This makes grilling Q6's
  literal-vs-identifier debate moot — there is no literal normalization to
  decide. [PORT]
- `module_hash` = SHA-256 of the whole manifest-stripped file.
- Per function: `id, name, line, end_line, hash`.
- `tested_at` = full RFC3339 timestamp (not a bare date).
- **Embed:** strip any existing manifest, trim trailing newlines, append
  `\n\n` + begin marker + `\n// ` + JSON + `\n` + end marker + `\n`. [PORT]
- **Extract:** find markers, strip `//` prefixes, JSON-parse. [PORT]
- **[JS]** comment syntax `//` works for JS/TS verbatim; marker strings rename
  `mutate4go` → `mutate4js`.

---

## 6. Coverage

- **[JS] format: LCOV** (mutate4go reads Go coverprofile). Reuse crap4js's LCOV
  parser and suffix-based path matching.
- **[PORT] gate = line coverage.** mutate4go's `Covered(profile,file,line)` is
  true iff the line is inside a segment with `Count > 0`. LCOV equivalent:
  `DA:<line>,<count>` with `count > 0`. **Branch (`BRDA`) data is ignored** —
  matching mutate4go and correct on purpose (branch-gating would suppress real
  survivors; grilling Q5).
- **[PORT] partition:** sites split into `covered` / `uncovered` by that gate.
- **[JS] acquisition:** instead of `<test-command> -coverprofile=PATH`, run
  `--cov-cmd` once (must emit LCOV), or read `--lcov PATH`, or `--reuse-coverage`
  from a default path (e.g. `coverage/lcov.info`). `--reuse-coverage` with no
  file present → the same hard error mutate4go emits.

---

## 7. Run loop **[PORT]**

From `Mutate()` / `runMutations*`:

1. Strip manifest from source, write the stripped file (analysis content).
2. Discover sites + functions; build current manifest; diff vs previous manifest
   → `changed` function IDs.
3. Acquire coverage (§6); partition covered/uncovered.
4. `effectiveSinceLastRun = --since-last-run OR (manifest exists AND not
   --mutate-all AND not --lines)` — **differential is the default once a manifest
   exists.**
5. `selectSites`: from covered sites, drop those not in `--lines` (if set) and,
   when differential, drop those whose FunctionID is unchanged.
6. Print header (§8); print uncovered list when not differential and no `--lines`.
7. **Baseline:** run `--test-command` once with no mutation; it must pass, and
   its duration sets `timeout = max(1s, timeout-factor × baseline)`.
8. Save `.mutate4js.bak`; for each selected site: apply mutant → write file →
   run test command with timeout → classify → restore original. Statuses:
   - non-zero exit → **killed**
   - timeout → **timeout** (counted as killed in the report)
   - zero exit → **survived**
9. Restore original, print report (§8), embed fresh manifest, cleanup backup.

**[PORT] crash safety:** on the next run, if a `.bak` exists (previous run
interrupted), restore it first and print
`Restored source from backup (previous run was interrupted).`

---

## 8. Output format **[PORT]** (reproduce strings verbatim)

**Header:**
```
Mutation run: <file>
Total mutation sites: <n>
Covered mutation sites: <n>
Uncovered mutation sites: <n>
Changed mutation sites: <n>
Manifest exists: <true|false>
Selected mutation sites: <n>
```
Plus `Warning: <n> mutation sites exceeds threshold <m>.` when over warning, and
`Mutation workers: <n>` when `--max-workers > 0`.

**Uncovered block** (only when not differential and no `--lines`):
```
Uncovered mutations:
  line <L> <desc> <functionID>
```

**Per-mutant progress:** serial `[i/total] <status> line <L> <desc> <functionID>`;
parallel inserts `worker-<k>` after `[i/total]`.

**Final report:**
```

Mutation Report
===============
Killed: <killed+timeout>
Survived: <survived>
Uncovered: <uncovered>

Survivors:
  line <L> <desc> <functionID>
```
(Survivors block only when survived > 0.) `<desc>` = `"<original> -> <mutant>"`.

**`--scan` output:**
```
Mutation scan: <file>
Total mutation sites: <n>
Changed mutation sites: <n>
Manifest exists: <true|false>
```
(+ warning line if over threshold). `--update-manifest` prints
`Updated manifest: <file>`.

---

## 9. Parallel workers — **[PORT] with [JS] cost caveat**

mutate4go copies the whole project tree into
`target/mutation-workers/worker-N/` (skipping `.git`, `target`, Go caches), runs
each worker's test command with `cwd = workerRoot`, and requires the source file
to live inside the working directory.

- **[PORT]** the copy-isolated-worker model, the in-cwd requirement, per-site job
  queue, stable-Index result sort, "stopped after k/n results" error.
- **[JS] caveat — `node_modules`.** Copying `node_modules` per worker is
  prohibitively expensive. Deviation: skip-list must include `node_modules`,
  `.git`, `coverage`, and the workers dir; **symlink `node_modules`** into each
  worker root instead of copying (so the test command resolves deps). Worker
  output dir: `.mutate4js/workers/` rather than `target/`. This is the only place
  the port needs real JS-specific engineering beyond renaming.

---

## 10. Plan fabrications corrected (do not trust the old plan on these)

| Plan claimed | Reality (mutate4go source) |
|---|---|
| Hash = FNV-1a | SHA-256 |
| Normalize identifiers→`_ID`, literals→`_LIT` | whitespace-collapse only |
| Manifest = per-function `// fn:name hash=… lines=…` comments | single JSON object between begin/end markers |
| Operators include Unary (`-a`,`!a`) and Null-return | no such operators |
| Flag set = 8 listed flags | also `--update-manifest`, `--lines`, `--mutation-warning`, `--timeout-factor`, `--verbose` |
| Coverage implicit from `--test-command` | Go appends `-coverprofile`; JS must split into `--cov-cmd`/`--lcov` |

---

## 11. Open (genuine) questions

- LCOV default path for `--reuse-coverage` / `--cov-cmd` output discovery
  (`coverage/lcov.info` is the common Vitest/Jest/c8 default — confirm).
- Whether to mutate `===`/`!==` (no mutate4go analog) — default **no** for
  fidelity; revisit if field use shows demand.
- `node_modules` symlink vs hardlink-copy for parallel workers on macOS/Linux
  (symlink is simplest; verify test runners resolve through it).

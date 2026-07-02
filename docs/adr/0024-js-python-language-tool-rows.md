---
status: accepted
---

# JS/TS and Python join the language tool table via a fork article

Upstream's Language tool table in `engineering.prompt` covers Go, Clojure, and Java, each backed by a `github.com/unclebob/...` trio (mutation, CRAP, DRY). The fork also runs JS/TS and Python projects, and fork-owned ports of the same trio are now released: `mutate4js` (npm), `@gabadi/crap4js` (npm), `mutate4py` (PyPI), `crap4py` (PyPI), and `drywall` (one Rust binary serving DRY for both languages). Port design and per-language divergences live in `docs/tool-analysis-crap-dry-mutation.md`.

**The rows live in a new additive article, `fork-languages.prompt`, not in `engineering.prompt`.** The prompt bundle walk (ADR 0017) injects every `*.prompt` under `constitution/articles/`, so a new article reaches every role without touching the upstream file. `engineering.prompt` is upstream-active — its startup-tools section changed three times in recent upstream history — so editing the table in place would be a permanent merge-conflict surface, against ADR 0001.

**Procurement diverges by necessity.** The upstream startup rule procures the latest tools from the listed `unclebob` GitHub repos. That cannot work for these rows: `crap4js`'s GitHub source is private (npm registry only) and `drywall` ships prebuilt release binaries with no registry. The article states registry/release procurement per row.

**Branch-coverage LCOV is doctrine, not advice.** All four CRAP/mutation ports score from LCOV BRDA records. coverage.py and the JS runners emit those only when branch coverage is explicitly enabled; without it the tools mis-score silently rather than fail. The article carries the per-language coverage commands.

**`setup-swarm` reads both tables.** Steps 1 and 2 read the fork article alongside `engineering.prompt`, so JS/TS and Python become offerable stacks and their tools install by the stated method.

## Pending implementation

- `six-pack`: carry `fork-languages.prompt` and the `setup-swarm` edits — the article only takes effect on branches whose worktrees contain it.

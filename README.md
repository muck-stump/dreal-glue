# dreal

Glue repository for testing **dreal4** across versions and environments.

## What is what

- `dreal4/` is a git submodule of the **actual repository**: dReal's
  source code, build fixes, tests, and its own README live there, and
  everything that changes solver behavior happens there (in small,
  reviewable commits) — never here.

- This repository (`dreal`) is the glue that holds things together when
  multiple versions of things need to be tested: it pins *which* commit
  of dreal4 sits in the tree, and over the runs it will hold the test
  harness (run/collect scripts), the per-run artifacts (one sorted list
  of failing test targets per run), and the A/B comparison reports
  between versions and environments. It contains no solver code.

Keeping the harness outside dreal4 is deliberate: a checkout under test
must be bit-for-bit identical to the commit being compared, so the
instrumentation cannot live in the same tree. Conversely, conclusions
and status findings get written back into `dreal4/README.md` as normal
docs commits — tooling out, conclusions in.

## The A/B this workspace exists for

dreal4 was modernized so it builds on a current Apple-Silicon Mac
(branch `modernize-macos`, 13 commits of build/tooling fixes on top of
the original code). The open question: how do its tests compare to the
original implementation when both are built in a controlled reference
environment?

Matrix (a "cell" = code × environment):

| cell | code | environment | state |
|---|---|---|---|
| A | base `f93bdcc` (original, pre-modernization) | reference container (Ubuntu) | **measured: 445/445 pass** |
| B | branch `e6d31b4` (`modernize-macos` tip, current submodule pin) | reference container | **measured: 445/445 pass** |
| C | branch `e6d31b4` | this Mac (macOS, Apple Silicon) | **measured: 445 tests, 303 pass / 142 fail** |
| D | base `f93bdcc` | this Mac | doesn't even configure/build — that is why the modernization exists; out of scope (build-level, not test-level) |
| E | branch `e6d31b4` (same code as B) | **modern Ubuntu**: Ubuntu 24.04 container (gcc 13, Python 3.12, gmp 6.3.0) | **measured: 444/445 pass, 1 fails to build (GCC≥13 warning), behavioural diff vs B = none** |
| F | branch `e6d31b4` (same code as B) | **modern Fedora**: Fedora 43 container (gcc 15, Python 3.14, nlopt 2.10) | **measured: 443/445 (same build failure + `timer_test` flake), behavioural diff vs B = none** |

Three comparisons, three questions:

- **A vs B** (same environment): did our 13 commits change behavior?
  Expected difference: **none** — and measured difference is none: both
  cells ran the identical 445 targets, 445/445 pass each, `comm -3` of
  the failing lists is empty (full evidence + method: [`report.md`](report.md)).
  Had it been non-empty, any target failing in B but passing in A would
  be a regression we introduced → fix/revert in dreal4. Known
  cross-platform suspects if it is non-empty: the `.bazelrc` `-Wno-error`
  relaxation, the `python_configure.bzl` distutils probe, the
  `optional.hpp` emplace port.
- **B vs C** (same code): which failures are environment? These are
  recorded and attributed, not "fixed" by touching solver code.
- **B vs E** and **B vs F** (same code, newer OS): did OS modernization
  in general move any test outcome? One variable per cell — same commit,
  same ibex commit, same Bazel 7.0.0, same harness — only the
  distribution (and its compiler/Python/system libraries) changes.
  Measured: **no behavioural change** — target sets identically 445,
  everything that built passed on both; the whole delta is one target
  that GCC ≥ 13 refuses to build (`-Wdangling-reference` false positive
  under `-Werror`) plus the known `timer_test` flake. Evidence +
  prediction scorecard: [`report.md`](report.md); the environment-side
  container accommodations and the pre-registered predictions:
  [`harness/NOTES.md`](harness/NOTES.md).

### Ground rules (from the maintainer)

1. Never change dreal4's solver behavior — only build/tooling
   modernization, and never turn a passing test into a failing one
   relative to cell A.
2. A difference only *counts* (is worth reporting as a real divergence)
   if the success/failure outcome differs from the original
   implementation built in the reference container. Differences
   attributable to the environment — dependency math (ibex build),
   floating point, host Python — are expected categories: document
   them, don't touch solver code for them.

## How the tests work (needed to read the artifacts)

One entry point everywhere: `bazel test //...` — builds and runs 445
test targets, each sandboxed, logging to
`bazel-out/<config>/testlogs/<target>/test.log`; `bazel test` prints a
`PASSED`/`FAILED` line per target. Four kinds:

- `smt2_test` / `dr_test`: a `py_test` (see `tools/dreal.bzl`) that runs
  `dreal foo.smt2` and **line-diffs stdout against the checked-in
  `foo.smt2.expected`** (`difflib.unified_diff`, exit 1 on mismatch).
  The behavioral oracle is therefore plain text files like
  `dreal/test/smt2/ea_01.smt2.expected` → `delta-sat with delta = 0.001`.
- `dreal_cc_test`: compiled gtest binaries (assertions in source).
- `*_cpplint`: `py_test`s running the vendored cpplint over sources —
  host-Python dependent.
- Python API tests: `unittest` scripts in `dreal/test/python`.

**Comparison artifact:** for each cell, the *sorted list of failed
target labels*. Convention for this repo (once the harness exists):

```
runs/failed.A.txt  runs/failed.B.txt  runs/failed.C.txt   # sorted labels
report.md                                                # comm -3 diffs + attribution
```

Compare lists with `comm -3 runs/failed.A.txt runs/failed.B.txt`;
never compare raw counts (equal counts can hide swapped targets).

### Python interpreter history (evidence boundary)

Cell C's recorded numbers (445 tests, **303 pass / 142 fail**) were
measured under the host's **Python 3.15.2** — Homebrew's unversioned
`python3`, which had moved to `python@3.15` two days earlier. The 119
`*_cpplint` failures are that interpreter, not this OS or this code:
`import sre_compile` (gone in 3.15, still present — deprecated — in
3.12/3.14, verified) is all cpplint needs to die at import time.

**The last dreal4 commit measured under Python 3.15 is `e6d31b4`** — the
state recorded above and mirrored in `dreal4/README.md` at that commit.
From the commit that follows this note, dreal4 pins its macOS test runs
to **Python 3.14** (`.bazelrc` macOS section, prerequisite
`brew install python@3.14`); the re-measurement at the new pin is
recorded as cell **C2** below. This measurement is superseded, not
deleted: it stays the record of what 3.15 does to the suite, and it is
what proves which bucket of failures is Python-version-driven.

## Known state of cell C (recap; authoritative copy in dreal4/README.md)

See `dreal4/README.md` → “Testing on macOS: Current Status” for the full
write-up. Summary of the 142 failures in 445:

- **119** `*_cpplint` — vendored cpplint does `import sre_compile`,
  removed in Python ≥3.13 (host Python issue; intentionally not patched
  yet).
- **21** answer `unsat` where `delta-sat …` is expected, clustered in
  the `forall`/optimization paths (`Minimize`, `exist_forall_*`,
  `ea_*`, `.dr cost:`, cav18 benchmarks). Preliminary debugging
  localizes a wrong answer to an `IbexFwdbwd` backward contraction
  emptying a box component that does not occur in the constraint;
  deliberately left source-unchanged pending the A/B.
- **1** `get_value_01` — one-ULP model difference (FP drift expectation).
- **1** `timer_test` — `elapsed()==0` timing flake.

Predictions to score against cells A/B: cpplints pass in the container
(old Python); the 21 pass there too (→ env-caused, mac toolchain/ibex);
`get_value_01` passes (`.expected` values were recorded in the x86
world); `timer_test` may flake everywhere.

## Reference environment (cells A and B)

Container recipe the repo itself supports:

- Image: **`ubuntu:22.04`** — CI tested 20.04 and 22.04; prefer 22.04
  (20.04, the `Dockerfile` base, is EOL). Inside:
  `setup/ubuntu/22.04/install_prereqs.sh` then `bazel test //...`.
  The script already pins **Bazel 7.0.0** (same as `.bazelversion`).
- Known caveats (all environment-side, therefore fixable inside the
  container without touching behavior):
  - `libibex-dev` comes from `ppa:dreal/dreal` (Launchpad). Fallback if
    undesired/unavailable: build ibex 2.7.4 from its release tarball.
  - the script downloads `bazel_…-linux-x86_64.deb`; on an arm64
    machine swap in `-linux-arm64.deb` (and recompute the sha256).
- Architecture: arm64 podman machine is the primary pick (native speed,
  matches cell C's architecture); amd64 (`--rosetta`/qemu emulation) is
  the upstream arch, useful only as a tiebreaker. Expect a cold full
  build to take on the order of an hour; keep one Bazel cache per
  checkout (separate output bases).
- Tier-0 (minutes, no build): the prebuilt `dreal/dreal4` image on
  Docker Hub has a reference solver binary — run cell C's failing
  `.smt2`/`.dr` inputs through it and diff against `*.expected` for an
  indicative verdict. Caveats: likely amd64 emulation and the image
  may lag 4.21.06.2 → indicative only, cell A is authoritative.

## Host environment of cell C (for reference)

macOS on Apple Silicon (arm64), Apple clang 21, system Python 3.15,
Homebrew at `/opt/homebrew`; ibex 2.7.4 from the formula vendored in
`dreal4/setup/mac/ibex@2.7.4.rb` (published into the local
`dreal4/local` Homebrew tap by `dreal4/setup/mac/install_prereqs.sh`);
`bazel` comes from bazelisk and is pinned to 7.0.0 via
`dreal4/.bazelversion`. Builds/tests run with cwd inside `dreal4/`
(never from this glue root).

## Layout

```
dreal4/            submodule → git@github.com:muck-stump/dreal4.git
                   .gitmodules pins the `modernize-macos` branch
harness/           test harness: one Containerfile* per environment image,
                   cells.env (commit × image × recipe per cell),
                   run-all.sh / run-cell.sh / collect.sh, install-*.sh,
                   in-container-test.sh (the driver baked into every image)
runs/              per-cell artifacts: failed.<cell>.txt (comparison artifact),
                   completeness.<cell>.txt, env-manifest.<cell>.txt, *.log
report.md          the A/B/B-vs-C (+B-vs-E/F) diffs + attribution
```

This superproject currently has **no remote** (local repo only).

## Usage

One entry point for a round of container cells (missing image → built on
demand; two cells in parallel at the measured budget):

```bash
harness/run-all.sh E F      # → runs/failed.{E,F}.txt + comm -3 diffs vs cell B
```

Single-cell pieces (what run-all.sh drives), and the A/B reference round:

Create the workspace (submodule included):

```bash
git clone --recurse-submodules <this-repo>
cd dreal
git -C dreal4 log --oneline -1     # show the pinned commit
```

Check out a different version under test (cell A = base), then record
the new pin:

```bash
git -C dreal4 fetch origin
git -C dreal4 checkout f93bdcc      # the pre-modernization base
git add dreal4                      # done from this (super)repository
```

Note: `git submodule update --remote` moves the submodule to the tip of
the branch named in `.gitmodules`; comparison runs must pin explicit
commit ids instead, as recorded in the reports.

## Status / next steps

Done: dreal4 modernization (13 commits, all pushed), cell C measured
and documented in `dreal4/README.md`, this workspace scaffolded, podman
installed and its machine created (6.1.4, applehv, arm64 native,
8 CPU / 12 GiB / 60 GiB; this version offers no `--rosetta` flag, so the
amd64 tiebreaker arch is out of scope), the A/B harness written under
`harness/` (see `harness/NOTES.md` for decisions, root causes and
checklists), **cells A and B measured — 445/445 pass each, zero A/B
diff — and `report.md` produced with the attribution of cell C's
failures to the environment.**

Not done, in order:

1. Fold the conclusions from `report.md` back into `dreal4/README.md`
   as documentation commits (submodule deliberately untouched so far).
2. Optional: tier-0 smoke run against the prebuilt `dreal/dreal4` image.
3. Optional follow-up round: the `gmp_repository.bzl` arch-probe fix **and
   the round-2 `-Wdangling-reference` build fix** as normal dreal4
   commits → re-pin → fresh A′/B′ pair (until then, the image's gmp.h
   symlink carries both cells equally, and GCC ≥ 13 keeps one test
   unbuildable).

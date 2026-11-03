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
| A | base `f93bdcc` (original, pre-modernization) | reference container (Ubuntu) | **to run** — the baseline |
| B | branch `e6d31b4` (`modernize-macos` tip, current submodule pin) | reference container | **to run** |
| C | branch `e6d31b4` | this Mac (macOS, Apple Silicon) | **measured: 445 tests, 303 pass / 142 fail** |
| D | base `f93bdcc` | this Mac | doesn't even configure/build — that is why the modernization exists; out of scope (build-level, not test-level) |

Two comparisons, two questions:

- **A vs B** (same environment): did our 13 commits change behavior?
  Expected difference: **none**. Any target failing in B but passing in
  A is a regression we introduced → fix/revert in dreal4. Known
  cross-platform suspects if it is non-empty: the `.bazelrc` `-Wno-error`
  relaxation, the `python_configure.bzl` distutils probe, the
  `optional.hpp` emplace port.
- **B vs C** (same code): which failures are environment? These are
  recorded and attributed, not "fixed" by touching solver code.

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
runs/              (planned) one failed.<cell>.txt per completed run
report.md          (planned) the A-vs-B / B-vs-C diffs + attribution
```

This superproject currently has **no remote** (local repo only).

## Usage

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
and documented in `dreal4/README.md`, this workspace scaffolded.

Not done, in order:

1. Install podman (not yet on this machine):

   ```bash
   brew install podman
   podman machine init --cpus 8 --memory 12288 --disk-size 60
   ```

   Add `--rosetta` if `podman machine init --help` offers it (enables
   amd64 emulation).
2. Write the harness here (small commits): cell runner inside the
   container, `runs/failed.<cell>.txt` collection, list diffs,
   optional tier-0 smoke run against the `dreal/dreal4` image.
3. Run cells A and B, produce `report.md`, then fold the conclusions
   back into `dreal4/README.md` as documentation commits.

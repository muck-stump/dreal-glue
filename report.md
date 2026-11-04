# A/B report: dreal4 base vs `modernize-macos` in the reference container

**Verdict: no behavioural drift.** The 13 modernization commits change
nothing observable: cells A and B executed the *identical 445 test targets*
and both passed **445/445**. `comm -3 runs/failed.A.txt runs/failed.B.txt`
is empty (both files are 0 bytes).

## Matrix — results

| cell | code | environment | state |
|---|---|---|---|
| A | base `f93bdcc26b62abdcc30ad7de6046729bb48016b9` | reference container | **measured: 445/445 pass** (bazel rc 0) |
| B | `e6d31b485d3ed828725e2c093c610031def17a3c` (`modernize-macos`) | reference container | **measured: 445/445 pass** (bazel rc 0) |
| C | `51c93b9` (= B + macOS pin/docs commits; the submodule pin) | this Mac (macOS, Apple Silicon), Python 3.14 pinned | measured: 445, 423 pass / 22 fail |
| D | `e6d31b4` (same code as B) | Ubuntu 24.04 container | measured: 444, 444 pass / 1 unbuildable; behavioural diff vs B = none |
| E | `e6d31b4` (same code as B) | Fedora 43 container | measured: 444, 443 pass / 1 unbuildable / 1 flake; behavioural diff vs B = none |

(Letters were standardized after round 2: old C2 → C, old E → D, old F →
E. A pre-harness probe of cell A’s code on this Mac — doesn't configure,
build-level, why the modernization exists — predates the scheme and has no
artifacts. Older readings, including the Python 3.15 era measured 303/142,
live in this file's git history; `harness/summary.sh` regenerates the
current view from `runs/`.)

**A vs B (same environment):** target-set diff *and* failing-set diff are
both empty → ground rule 1 holds: no passing-in-A test fails in B, and no
build regression either direction (cell A builds and links fine in the
reference container).

## Method

- **One image, both cells**: `dreal-ref:22.04`, id
  `0c0567ed3fc1ec3283873645964e1ccae668eb43df9c1faa9fdd8dfaef1fd410`
  (manifest incl. full `dpkg -l`: `runs/env-manifest.txt`). ubuntu 22.04.5,
  arm64, bazel 7.0.0 (sha-pinned), g++ 11.4.0, ibex 2.7.4 source-built at
  `/opt/libibex/2.7.4`, clp 1.17.5, nlopt 2.7.1, gmp 6.2.1.
- **Checkouts bit-for-bit the pins**: each cell's source is `git archive`
  of the pinned commit unpacked into its own volume; the submodule stayed
  clean throughout — *zero* changes to any code under test. Every fix made
  during bring-up lives in `harness/` (image recipe) and is therefore
  identical for A and B by construction.
- **Run**: `bazel test -k --cache_test_results=no //...` per cell, in
  parallel (machine 8 CPU / 12 GiB / 60 GiB; each cell `--jobs=4`,
  1500 m JVM heap, own output base/cache volume). Warm rerun ≈ 3 min wall
  for *both* cells.
- **Artifacts** (committed): `runs/failed.{A,B}.txt` (sorted failing labels —
  both empty), `runs/completeness.{A,B}.txt` (— `Executed 445 out of 445
  tests: 445 tests pass.` + `no loading errors`), `runs/env-manifest.txt`.
  Raw logs and passed-label lists kept locally (gitignored).

Target-set breakdown (identical in A and B; `comm -3` of the full PASSED
label lists is empty): 240 `smt2`/`dr` behavioural-oracle tests
(line-diff of dreal stdout vs checked-in `.expected`), 119 `*_cpplint`,
86 compiled gtests / Python-API tests.

## B vs C (same code): attribution of cell C's 142 failures

Every prediction in the workspace README scored **confirmed**:

| cell-C failure class | count | A/B container result | attribution |
|---|---|---|---|
| `*_cpplint` (host Python ≥ 3.13 dropped `sre_compile`) | 119 | all 119 **pass** (container Python 3.10.12) | environment: host Python, not code |
| `unsat`-instead-of-`delta-sat` cluster (`forall`/optim paths) | 21 | all **pass** on both commits | environment: mac toolchain/ibex build — *not* the modernization, *not* the base; solver answers are correct in the reference env |
| `get_value_01` (one-ULP model difference) | 1 | **pass** | environment: FP/toolchain drift; `.expected` values hold on linux/arm64/g++11 |
| `timer_test` (`elapsed()==0`) | 1 | A passed; B failed **once**, then passed on rerun with `--cache_test_results=no`; sources byte-identical between pins | timing flake (non-deterministic), as predicted |

Conclusion: cell C's 142 failures are 100% environment-attributable and
none of them warrant touching solver code (ground rule 2 respected: nothing
was "fixed" in dreal4 for them).

---

## Round 2 — same code, modern OS: cells E and F

**Verdict: OS modernisation moves no test behaviour.** Cells E (Ubuntu
24.04) and F (Fedora 43), both running cell B's exact commit `e6d31b4`,
executed the **identical 445-target set** and produced no behavioural
difference: every target that built, passed — the full 240-target
smt2/dr line-diff corpus, the gtests, the Python API tests and both
119-target cpplint suites included. The entire delta vs cell B is one
target that no longer *builds* on GCC ≥ 13, plus the known timer flake.

### Matrix — round 2

| cell | code | OS / toolchain | result |
|---|---|---|---|
| B | `e6d31b4` | Ubuntu 22.04.5, gcc 11.4, Python 3.10.12, gmp 6.2.1, clp 1.17.5, nlopt 2.7.1 | **445/445 pass** (reference) |
| E | `e6d31b4` | Ubuntu 24.04.5, gcc 13.3, Python 3.12.3, gmp 6.3.0, clp 1.17.9, nlopt 2.7.1 | **444/445 pass, 1 fails to build** (bazel rc 1) |
| F | `e6d31b4` | Fedora 43, gcc 15.3, Python 3.14.8, gmp 6.3.0, clp 1.17.10, nlopt 2.10.0 | **443/445 pass, 1 fails to build, 1 fail** (bazel rc 1) |

Images, with full package manifests in `runs/env-manifest.<cell>.txt`:
E = `dreal-ref:24.04` `3e25babda5a7dcb6…`, F =
`dreal-ref:fedora-43` `1066b7d27b9ee2d2…`. Held constant vs B: the
commit, ibex `352eeeb` source-built at `/opt/libibex/2.7.4`, Bazel
7.0.0 (sha-pinned), the driver, `--cache_test_results=no`, the machine
budget, and one image per cell pinned by id. Target-set check (equal
counts can hide swapped targets): `comm -3` of the full PASSED label
lists is empty for B↔E and B↔F — 445 labels each, pairwise identical.

### `comm -3` vs cell B (col 1 = B-only, col 2 = cell-only)

```
B vs E:  	//dreal/contractor:contractor_ibex_fwdbwd_test
B vs F:  	//dreal/contractor:contractor_ibex_fwdbwd_test
	//dreal/util:timer_test
```

### Attribution

1. `contractor_ibex_fwdbwd_test` — **build-level, and it is the
   compiler**: `-Werror=dangling-reference` on
   `const auto& x = ibex::ExprSymbol::new_();` at
   `dreal/contractor/test/contractor_ibex_fwdbwd_test.cc:134-136`,
   identical failure in E (gcc 13) and F (gcc 15) and in no other file in
   either cell. `-Wdangling-reference` is new in GCC 13, and here it is
   wrong: ibex's header declares
   `static const ExprSymbol& new_(const Dim& = …)` — a factory returning
   a reference to a heap object, not a temporary; it becomes fatal purely
   because dreal builds its own targets with `-Werror`. The target shows
   as `NO STATUS` (never executed), so this is *not* a test outcome
   change — and cell C (Apple clang) builds and passes it.
   Not "fixed": cells stay pinned. Candidate for the pending follow-up
   dreal4 round alongside `gmp_repository.bzl` (e.g.
   `-Wno-dangling-reference` for the target) → then a fresh A′/B′ pair.
2. `//dreal/util:timer_test` in F only — the known timing flake:
   failed once in B round 1, passed in B round 2 and in E, failed here.
   Non-deterministic, recorded honestly in `runs/flaky.F.txt` /
   `failed.F.txt`.

### Prediction scorecard (pre-registered in harness/NOTES.md)

| prediction | verdict |
|---|---|
| E ≈ 445/445 modulo a gcc-13 `-Werror` surprise | kept — narrowly: the single miss *is* a gcc-13 `-Werror` surprise (build level) |
| E: 119 cpplints pass | ✅ 119/119 |
| F: 119 cpplint failures (`sre_compile` gone since Python ≥3.13) | ❌ **wrong**: all 119 **pass** on 3.14.8 — `import sre_compile` still works there (DeprecationWarning; verified in both images). The module survives at least through 3.14; cell C's host Python (3.15) is where it's gone. The cpplint class is therefore *host Python ≥3.15*, not "modern Python ≥3.13", and dreal4/README's wording needs correcting in the docs round |
| E+F: 21 unsat-cluster + `get_value_01` pass | ✅ all pass (spot-checked `ea_01`, `exist_forall_04`, `minimize_03`, both `api_test`s, `get_value_01`) — the wrong-answer cluster stays mac-only, and does *not* reappear with nlopt 2.10 / clp 1.17.10 / gcc-15 |
| F: gcc-15 `-Werror` build risk | ✅ realized, as the one build failure above (gcc-13 too) — and only that one |
| `timer_test` may flake anywhere | ✅ flaked in F |

### What rounds 1–2 now say about cell B vs C

Of cell C's 142 failures, **none appear on any modern Linux OS**:

- 119 cpplint → needs Python ≥3.15 (verified not distro-level: Fedora
  43's stock 3.14 passes all of them; so does noble's 3.12);
- 21 `unsat`-instead-of-`delta-sat` + the 1-ULP `get_value_01` →
  mac-specific: two *newer* Linux stacks (gcc 13/15, nlopt 2.10, clp
  1.17.9/10, same ibex source) all answer correctly;
- 1 `timer_test` → non-deterministic, seen on Linux too (F), just later.

So: OS modernisation in general ⇒ zero behavioural drift; the only
Linux-modern delta is a compiler warning at build level, and cell C's
failures are 100% macOS-host environment (unchanged conclusion,
now cross-checked against two more distributions).

### Reproduce round 2

```bash
podman machine start
harness/run-all.sh E F                       # images built on demand; runs, collects, diffs vs B
comm -3 runs/failed.B.txt runs/failed.E.txt   # → 1 line: the build-failed target
comm -3 runs/failed.B.txt runs/failed.F.txt   # → that line + timer_test
```

---

## Round 3 — cell C2: macOS re-measured under a pinned Python 3.14

Status: **measured — every prediction held** (tip `f37a1c1` = the three
pin/note commits on top of `e6d31b4`).

### Why / what changed vs cell C

Cell C's 303/445 ran under Homebrew's then-default `python3` = **3.15.2**
— the boundary is recorded in README "Python interpreter history":
**`e6d31b4` is the last commit measured under 3.15.** dreal4 now treats
**Python 3.14 as a prerequisite on macOS** and pins it itself:

- dreal4 `6a0c0cc` — `.bazelrc` `build:macos` section →
  `--repo_env=PYTHON_BIN_PATH=/opt/homebrew/bin/python3.14`, placed above
  the `try-import user.bazelrc` (later options win ⇒ locally
  overridable); Linux keeps PATH's python3, so cells A/B/E/F are
  untouched by construction;
- dreal4 `1ea8627` — the missing-interpreter failure now names the
  prerequisite instead of a `--define` hint that stopped working long ago;
- dreal4 README — "Tested interpreter: Python 3.14" note (committed
  before this run, so the measured commit includes it).

Verification of the switch (done before running anything):
`external/local_config_python/BUILD` says
`interpreter_path = "/opt/homebrew/bin/python3.14"` and the include tree
is `python@3.14/…/include/python3.14`. (First attempt with `bazel query`
showed 3.15 — query does not apply `build:` sections; noted because the
repo rule only invalidates on an actual env change.)

### Prediction (to be scored after the run)

| # | prediction |
|---|---|
| 1 | 445 targets, `no loading errors`, `Executed … of 445` |
| 2 | **exactly the 119 `*_cpplint` labels flip** fail→pass vs cell C |
| 3 | everything else stays as cell C: the 21 `unsat`-cluster + `get_value_01` still fail (Python cannot touch solver answers); `timer_test` is a coin flip (C failed it, E passed, F failed) |
| 4 | ⇒ expected **421–422 pass / 445**, i.e. `failed.C2` = C's non-cpplint failures, `\|failed.C2\|` = 22–23 |
| 5 | **anything else moving = real signal** → stop and attribute before reporting |

### Scored (all five hold)

| prediction | result |
|---|---|
| 1 | ✅ `Executed 445 out of 445 tests: 423 tests pass and 22 fail locally`, `no loading errors` (runs/completeness.C2.txt, bazel rc 3) |
| 2 | ✅ **zero `*_cpplint` in `runs/failed.C2.txt`; 119/119 pass** — the causal flip: changing only the interpreter removed exactly that class |
| 3 | ✅ the failing 22 are exactly cell C's non-Python set: the 21 `unsat` cluster (api ×2, cav18 ×2, constrained_opt ×2, unconstrained_opt ×4, python api/gh154 ×2, ea ×2, exist_forall ×5, gh192/201 ×2, minimize_03) + `get_value_01`. `timer_test` **passed** this round — coin landed pass (C: fail, E: pass, F: fail, C2: pass ⇒ flaky, as scored in round 2) |
| 4 | ✅ **423/445** (band was 421–445 / fail-count 22–23) |
| 5 | ✅ the flip set is precisely the cpplint class — nothing else entered or left `failed.*` |

Net: cell C's 142 = **119 Python-version** (now fixed by prerequisite+pin,
not by touching a test) **+ 21 wrong-answer cluster + 1 ULP** (the mac's
real, Python-independent residual) + 1/0 flake. The direct C↔C2 contrast
upgrades the cpplint attribution from "deduced via Fedora" to
cross-experiment causal, on one machine, one variable.

Method otherwise identical to cell C: bare metal, same host, same
clang/ibex, `-k --cache_test_results=no //...`, artifacts
`runs/{bazel-test.C2.log,failed.C2.txt,completeness.C2.txt,
env-manifest.C2.txt,exit-code.C2.txt}`. Two variables technically moved
vs C: the interpreter *and* two dreal4 tooling commits on top of
`e6d31b4` (rc pin + failure message) — both are interpreter-selection /
message-only, no build input of any test target changes besides which
python runs the py_tests.

## Environment findings during bring-up (all resolved container-side)

These are tooling/portability observations for follow-up commits to
dreal4 proper — none were patched into the cells under test:

1. **`tools/gmp_repository.bzl` hardcodes the x86 multiarch tuple**
   (`/usr/include/x86_64-linux-gnu/gmp.h` + a Fedora path; arm64 Ubuntu has
   neither → `fail("Failed to locate gmp.h")`). Worst part: the loading-phase
   error silently **dropped ~259 test targets** (everything depending on
   `@gmp//:gmp`, i.e. most of the behavioural corpus) while bazel still
   printed `Executed 186 out of 186 tests` and exited only via rc 1 — first
   round of runs was invalid for this reason. Fixed in the image with a
   symlink to the file compilers already use. *Recommended next-round
   `.bzl` fix* (arch probe or both tuples), as a normal dreal4 commit.
   The harness now also records completeness so a partial run cannot pass
   unnoticed again (`runs/completeness.<cell>.txt`).
2. **ppa:dreal/dreal ships no arm64 binaries** (arm64 `Packages` index is
   empty, 20 bytes) → `libibex-dev` can't exist on this arch. Replaced by a
   source build of **the PPA's own source**: version string
   `2.7.4…git352eeeb…` = dreal-deps/ibex-lib @`352eeeb`, the same commit
   `Dockerfile.amazonlinux` uses, installed at the prefix `workspace.bzl`
   already probes (`/opt/libibex/2.7.4`).
3. **ibex snapshot delta vs cell C**: the mac formula pins tag
   `ibex-2.7.4_13` = commit `26eeeaa` (2021) — same *version* as
   `352eeeb` (2022), different *tree*. Version-identical, so B-vs-C
   attribution wording should say "ibex 2.7.4, different upstream snapshot +
   different compiler/OS", not "same ibex". Does not affect A vs B (one image).
4. **Bazel 7.0.0 has no arm64 `.deb`** (upstream publishes x86_64 `.deb`
   only) → harness installs the official `bazel-7.0.0-linux-arm64` binary,
   sha256-verified against the release `.sha256` asset.
5. `add-apt-repository` fails without `gpg-agent` because upstream's script
   installs `software-properties-common --no-install-recommends` (upstream
   CI runners have gpg-agent preinstalled) → installed explicitly in the image.
6. ibex's `ibex.pc` bakes in `-msse3 -ffloat-store` → stripped post-install,
   identical to cell C's formula "Patch 3" (aarch64 g++ hard-errors on `-msse3`).

## Reproduce

```bash
podman machine start                                  # 8 cpu / 12288 MiB / 60 GiB
podman build -f harness/Containerfile -t dreal-ref:22.04 .
harness/run-cell.sh A & harness/run-cell.sh B         # parallel
podman logs -f dreal-cell-A                           # watch
harness/collect.sh A; harness/collect.sh B            # → runs/failed.{A,B}.txt + completeness
comm -3 runs/failed.A.txt runs/failed.B.txt           # → (empty)
```

## Remaining (per workspace README)

- Fold these conclusions into `dreal4/README.md` as a documentation commit.
- Optional: tier-0 smoke against the prebuilt `dreal/dreal4` image.
- Optional follow-up round: the `gmp_repository.bzl` portability fix (would
  be a 14th commit → justifies a fresh A'/B' pair afterwards).

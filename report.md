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

## Round 4 — the ibex swap (prediction pre-registered BEFORE the run)

**The one variable:** cell C (macOS) previously linked Homebrew's
`ibex@2.7.4 = 2.7.4_13`, tag-pinned to commit **`26eeeaa` (2021)**, where
cells A/B/D/E all source-build **`dreal-deps/ibex-lib@352eeeb`**. Cell C's
recipe now source-builds `352eeeb` too (prefix `~/.local/opt/ibex-352eeeb`,
resolved through `harness/shim-bin/pkg-config`; Homebrew's ibex untouched,
dreal4 checkout untouched, same commit `51c93b9`, same Python 3.14, same
driver). Everything else about C is byte-identical to the 423/445 run.

**Primary prediction (scoreable): ≥ 19 of the 22 failing targets flip to
pass** once mac runs the Linux cells' ibex commit. Predictions by class
(step-1 classification, harness/NOTES.md + conversation of record):

- **C1 (14, exactly-sat, `unsat` unlicensed): flip** — `exist_forall_{04,
  06, 07, 08, 10}`, `ea_beale`, `github_issue_192`, `minimize_03`,
  `//dreal/api:api_test`, `//dreal/test/python:{api_test,github_issue_154}`,
  `unconstrained_opt_{beale,eggholder,mccormick,poly1}`.
- **Mixed C1/C2 suite targets (3): flip** — `//dreal/api:cav18_*`.
- **C3 undecidable-by-eye (2): expected flip** — `ea_01`, `github_issue_201`.
- **C2 both-legal pair (2): may legitimately stay `unsat`** —
  `constrained_opt_rosenbrock_{cubic,disk}` (strict-open feasible set,
  unattained infimum: both answers legal under delta-semantics; if they do
  not flip, that is evidence for the both-legal reading, not a miss).
- **C4 value-drift (1): coin-flip, leaning stay** — `get_value_01`
  (one-ULP model diff; may be Apple-libm FP, not ibex).
- `//dreal/util:timer_test` is the pre-registered timing flake, excluded
  from scoring either way.

**Outcome that would falsify the ibex hypothesis:** cluster = 0 flips
(cluster pinned to toolchain: Apple clang codegen / `-ffp-contract` / libm
→ next step becomes the flag/libm bisect). Partial flip → two mechanisms;
split the survivors against the C1/C2/C3/C4 classes above.

Score of this round recorded below after the run.

### Round 4 score — **FALSIFIED** (0 of 22, not ≥19 of 22)

Measured after the swap (three cell C runs, identical cluster each time;
last run also absorbed the `install_name` hardening below, and reproduced
the prediction's own flake split: `timer_test` failed in run 1, passed in
runs 2–3 — stochastic, uncounted). `runs/ibex.C.txt` records the run's
believed ibex (`-L/Users/josh/.local/opt/ibex-352eeeb/lib`), triple-checked:

1. fetched `@ibex` repo's generated BUILD bakes our prefix (includes under
   `_Users_josh_.local_opt_ibex-352eeeb_*`, `-L` ours);
2. full cflags byte-match Homebrew's modulo the prefix (including
   `-frounding-math`) — the resolved configuration differs *only* in commit;
3. `otool -L` of the linked test binary resolves
   `/Users/josh/.local/opt/ibex-352eeeb/lib/libibex.dylib`.

**Verdict: the ibex *source commit* (`26eeeaa` vs `352eeeb`) is not the
mechanism.** All prediction classes failed to flip, including the 14 C1
"unsat-not-licensed" targets — so same-source-same-compiler-parity does not
move the cluster on this Mac. (Mechanism pointer from here: what macOS
changes that every Linux cell shares substitutes neither for — Apple clang
codegen + `-ffp-contract` defaults in dreal's *own* translation units, and
Apple libm (glibc-vs-libm `sin/exp/pow` in ibex/dreal evaluation). Reverse
arm — Linux cells against Homebrew's `26eeeaa` — pre-agreed next after this
one, flag/libm bisect (old step 5) after that.)

Hardening recorded: waf leaves the dylib's install name pointing at the
temp build directory (tests ran only until macOS's `/var/folders` purge
would remove it); `install-ibex.sh` now rewrites the id post-install, and a
`bazel clean` was needed once because link actions do not declare `-L`
directories as inputs (stale link keeps the old id until outputs are
invalidated — checked: fixed binary now records the prefix path).

**T-b prediction (pre-registered BEFORE the run): today's cell C recipe
plus `-ffp-contract=off` on both halves we control (dreal via CLI copt,
harness-built ibex rebuilt with `CXXFLAGS=-std=c++0x -ffp-contract=off`).**
Scoring against the frozen previous C list (`git status` shows 22 fails =
14 C1 + 3 mixed + 2 C3 + get_value_01, minus nothing; rosenbrock pair =
423/445 baseline):
- **≥15 of those 22 flip** → H1 (contraction usage in this Mac's
  translation) supported;
- **≤3 flip** → H1 falsified on the Mac too (post-T-a lean: this branch);
- 4–14 → partial: re-split survivors against C1/C2/C3/C4 classes → likely
  ≥2 mechanisms.
`timer_test` excluded (flake), C2 pair may legally stay (both-legal),
`get_value_01` scored but tolerated as libm-ish.

## Round 5 — trial T-a (record, no prediction needed) and T-b's registration

**T-a result (recorded after the fact — it was a measurement, not a run):**
compile-command inventory for one shared TU on cell C vs cell D
(`runs/T-a-compile-flags.txt`): explicit flags differ only in
diagnostics/defines (`_DARWIN_C_SOURCE`, `-fcolor-diagnostics`,
mac-only `-D_FORTIFY_SOURCE=1`, warning toggles) — **nothing FP-semantic
(`-ffast-math`, `-ffp-contract`, `-fno-*`) is set on either side**, so
results ride on tool defaults; both compile `-O2`. Default probes
(`a*b+c` same-expression vs statement-split, ARM64, `-O2`, metamorphic
`a*b+c` fusion count):
- apple clang (cell C): same-expr fused (1 fmadd), cross-statement NOT fused
  (= `-ffp-contract=on`-like default); `-ffp-contract=fast` fuses both (2).
- brew gcc-16 (mac): both fuse (2) — `fast`-like default.
- container gcc-13 (cell D): both fuse (2) — `fast`-like default.
⇒ the tool that fuses *more aggressively* (linux/gcc) is the clean one;
plain fusion is therefore not a mac-vs-linux differentiating factor a
priori, **lowering** H1's prior before T-b runs. Kept in the plan because
*which sites* each backend fuses still differs, and T-b is the decisive
mac-side intervention for H1.

**T-b score: H1 falsified.** Trial ran with the echoed receipt
`trial extra bazel args: --copt=-ffp-contract=off` (ibex also rebuilt with
`CXXFLAGS=-std=c++0x -ffp-contract=off`): failed set = frozen baseline's 22
**unchanged, 0 flips** (only `timer_test` appeared — its flake, excluded).
≤3-flip branch of the pre-registration taken: contraction usage in this
Mac's translation is not the mechanism.

## Round 5 — T-c, T-d, T-e predictions (registered before any of them run)

- **T-c** (libm value probe, mac python3 vs container python3, same
  expressions: sin/cos/exp/pow/sqrt/log at cluster-relevant arguments —
  eggholder scales, Ackley `exp(-0.02·√)` sums, π-adjacent, near-zero):
  **P(falsifiable form): every probe point differs by ≤ 4 ulp.** Split:
  >4 ulp anywhere ⇒ H2 (Darwin vs glibc libm) gains sharply; ≤4 everywhere
  with cluster absent/present elsewhere ⇒ libm divergence is real but
  far too small to own the linear-arithmetic `github_issue_192` ⇒ we rank
  OS-layer/compiler interplay above raw libm tables.
- **T-d** (same Mac, brew `gcc-16` for BOTH halves: ibex re-built with
  g++, dreal bazel toolchain via `CC=gcc-16`; Darwin/libm/SDK held):
  **P: the cluster persists (≥15 of 22 still fail)** — and the score
  branches: **persist** ⇒ mechanism is darwin-side (OS/SDK/libm/library
  interplay), compiler vendor exonerated on this Mac; **cleans (≤3 fail)**
  ⇒ mechanism is the Apple-clang compilation path, and the candidate C
  recipe fix becomes a `.bazelrc` macos `--repo_env=CC` pin (same pattern
  as the Python 3.14 pin).
- **T-e** (ubuntu 22.04 reference environment — cell A/B's exact image +
  packages — with `clang` substituted for gcc as toolchain; B's commit,
  cell-B environment otherwise byte-identical): **P: cluster remains
  absent (≤2 fail).** Branches: **absent** ⇒ clang-family alone is not
  sufficient; combined with T-d-persist this hands the finding to the
  darwin layer as a whole; **present (≥10)** ⇒ LLVM-family codegen is
  implicated and the apple-vs-llvm split becomes the next axis (clang-14
  vs clang-21 version skew noted as a caveat either way).

**T-d attempt 1 (recorded as-is): BUILD COLLAPSE.** One mechanical cause,
264×: bazel's apple config injects `-mmacos-version-min=11.0` (Apple-clang
dialect); gcc-16 demands `-mmacosx-version-min=` and dies before compiling
anything (122/445 executed = only python/cpplint targets; `failed.txt` 5-of-323
= the known under-listing pattern, caught by the completeness check this round
added). Not evidence about the hypothesis — infrastructure.

**T-d amendment (registered BEFORE attempt 2):** identical trial plus
`harness/shim-bin/gcc-16-compat` — a dialect shim that translates the one
deployment-target flag and drops six clang-only *warning* switches
(-Wthread-safety, -Wself-assign, -fcolor-diagnostics,
-Winconsistent-missing-override, -Wreturn-stack-address,
-no-canonical-prefixes), all shaken out mechanically against the exact
argv list. Semantics of the trial unchanged: same code, same -O2, same
Darwin SDK/libm, gcc-16 codegen for both ibex and dreal.
**Score branches identical to the original registration** (≥15 of 22 fail
→ darwin side; ≤3 → Apple-clang compilation path).

**T-d attempt 2 (record):** compiles got through (dreal's own sources died
only on the known gcc≥13 `-Wdangling-reference` false positive — the same
one cells D/E record) but **all 65 links failed**: bazel's CppLink hands
`@file.params`, the wrapper passes that single token to the shim, and
real gcc expands the response file *internally* — dodging the filter
(65× `-mmacos-version-min`, 65× `-fobjc-link-runtime`).
**Shim v2 (registered before attempt 3):** expand `@`-files inside the
shim first, then filter (adds `-fobjc-link-runtime` to the dropped
apple-dialect set). Trial semantics unchanged; scoring branches unchanged.

**T-d attempt 3 (record):** compiles 100% through except the pre-known
gcc≥13 `-Wdangling-reference` trio at
`dreal/contractor/test/contractor_ibex_fwdbwd_test.cc:134-136` — byte-
identical to cells D/E recorded position, i.e. that wire reproduced under
gcc-16/mac too. 64 links then died: bazel's CppLink driver = `gcc`
(no auto libstdc++, undefined `std::__cxx11::*` references).
**Shim v3 (registered before attempt 4):** append `-lstdc++` on
link-shaped invocations (detected via absence of -c/-E/-S/--syntax-only) —
still trial infrastructure; scoring branches unchanged.

**T-d attempt 4 (record):** 185/445 executed. Of the frozen 22: **8 executed
— all 8 STILL failing under gcc-16 (api_test, cav18×2, rosenbrock pair,
python api_test/154) — 0 flips among scored targets.** 14 never built
(they hang off `//dreal:dreal` which failed its final link). All compiles
pass; the only compile error remains the known `-Wdangling-reference`
trios. Remaining: 2 links, both one cause: brew's `libgmpxx.4.dylib` is
clang/libc++-built, gcc-16 references libstdc++-mangled `operator<<` ⇒ ABI
mismatch between toolchain and Homebrew's C++ dylibs (nlopt/clp/coinutils
link clean — gmpxx is the only clash).

**Shim v4 (registered before attempt 5):** build gmp (same brew version,
`--enable-cxx`, CC=gcc-16) into `~/.local/opt/gmp-gcc16`, shim prepends its
`lib/` on link lines. Trial semantics unchanged; scoring branches unchanged.

**T-d ATTEMPT 5: VALID FULL RUN — SCORED.** Executed 444/445 (1 fail-to-
build = the known `-Wdangling-reference` target, exactly cells D/E's
record; `BUILD DID NOT COMPLETE` flag = that one absent-from-status-row
case the completeness parser documents). Result vs frozen 22: **0 flips —
all 22 still fail under gcc-16** ⇒ **registered persist-branch taken:
mechanism is on the Darwin side; compiler vendor exonerated on this
Mac** (apple clang and brew gcc-16 both cluster, while gcc AND clang run
Linux)+additions: `contractor_ibex_fwdbwd_test` (build, known),
`timer_test` (flake), and 6 gcc-specific NEW failures to note as
toolchain-side curiosities, outside cluster scoring: `util:cds_test`,
`test:cds_priority_queue_test`, `python:{contractor,solver,symbolic}_test`.
Infrastructure log for the record (5 attempts): -mmacos-version-min
dialect → @params leak → gcc-doesn't-auto-link-libstdc++ → brew gmpxx
libc++ ABI (fixed by gcc-built gmp-6.3.0 `-std=gnu17` trial prefix, exact
`__ZlsRSoPK12__mpz_struct` symbol match) — all in `harness/shim-bin/gcc-16-compat`.

**T-e attempt 1 (record):** 122/445 — clang-14 rejects one copt:
`-Wno-deprecated-builtins` unknown → `-Werror,-Wunknown-warning-option`
(137×). Why no Linux cell ever showed this: gcc *silently ignores*
unknown `-Wno-*`, clang *errors* — the warning asymmetry itself. (The copt
comes from dreal's own config; harmless on the clang-21 Mac.)
**Attempt 2 (registered before running):** Containerfile.trial-clang adds a
container-side `clang-14-compat` wrapper dropping that one option — same class of image-side
accommodation as every other container cell; scoring branches unchanged
(pre-registration: cluster absent, ≤2 fails).

**T-e ATTEMPT 2: VALID FULL RUN (445/445 executed) — SCORED.** 7 fails:
**6 ∈ the frozen mac-22** (`cav18_{with,without}_local_opt`, `ea_beale`,
`exist_forall_06`, `get_value_01`, `minimize_03`) + `timer_test` (flake).
The ≤2 "absent" branch is taken as MISSED: the cluster **partially
reproduces on Linux under clang-14** (6/22), so LLVM-family codegen is now
implicated for that slice — but not enough for the ≥10 branch either; the
in-gap outcome is itself informative (matrix below).

## Round 5 outcome matrix — BOTH axes matter

Cluster reproduction count (out of the frozen 22), complete experiment grid:

| toolchain → / runtime ↓ | gcc | clang (LLVM family) |
|---|---|---|
| **Linux/glibc** | **0** — cells A/B/D/E (gcc 11/13/15) | **6/22** — T-e (clang-14 = attempt 2, 445/445 executed) |
| **Darwin/libm (this Mac)** | **22/22** — T-d (gcc-16, attempt 5, 444/445) | **22/22** — cell C baseline (apple clang 21) |

Readings (all pre-registered branches scored above; none of my directional
calls was right in full — T-d's persist hit, T-e's clean-commit missed into
the gap):
1. **Darwin side is the dominant axis**: *both* compilers give the full
   cluster on the Mac; *neither* pristine-Linux cell ever has (gcc), and
   clang only gets 6/22 there.
2. **Compiler family still matters within Linux**: 0 → 6 purely by
   swapping gcc for clang-14 at fixed glibc/runtime. The 6-slice
   (`exist_forall_06`, `ea_beale`, cav18/bench-optimization, minimize_03,
   get_value_01) = LLVM-family-sensitive targets.
3. The **16 mac-only remainder** (incl pure-linear `github_issue_192` —
   which T-e did *not* reproduce, upgrading it from "codegen?" to
   "Darwin-runtime") has no Linux-clang twin ⇒ candidates: Apple-clang-21-
   vs-14 version delta, Darwin runtime seam (T-c: ≤1 ulp libm, plausible
   only where margins are knife-edge — and 192's margin is 5.8e6, so raw
   value tables still don't explain it), fenv/SDK behavior of plain
   interval arithmetic.
4. Caveats honestly: T-d grafted libstdc++ + a gcc-built gmp trial prefix
   (its 6 extras and swings come from that heterogeneous link chain); T-e's
   shim dropped exactly one gcc-lnfluent line copt validated by the
   445/445-executed outcome; clang-14 vs apple-clang-21 version skew.

**Bookkeeping:** after scoring, cell C was restored to its canonical
recipe (default-tuning harness-ibex@352eeeb rebuild without trial
`CXXFLAGS`, apple-clang, no extra copts) and re-measured: 445/445
executed, fails = the frozen 22 + that run's known `timer_test` flake —
0 cluster drift. `runs/ibex.C.txt` records resolution; `hypotheses.md`
carries the leadger and ranked open questions.

**T-g — PRE-REGISTRATION (written before any run exists).**
Question: is the 22-cluster a property of *Apple's* clang fork, or does it
survive a different frontend at fixed OS/SDK/libm/HW? Trial = rebuild both
halves with **LLVM-project clang** (brew `llvm`, keg-only, unmodified
upstream build; Darwin/userspace/silicon untouched; ibex source constant
at `352eeeb`, rebuilt into its own trial prefix as in T-d — the only Δ vs
C baseline = the compiler frontends apple-clang-21 → upstream-LLVM).
Dialect probes (capability checks, no outcomes seen): llvm clang accepts
`-mmacos-version-min=11.0`, `-Wno-deprecated-builtins`.
Scoring pre-commit: strict-fail count among the frozen 22 (same rubric as
T-d: `timer_test` flake and `get_value_01` ULP excluded; C2 rosenbrock
pair tolerated; an incomplete build invalidates the run → rerun).
Scoring branches:
- **P-persist (recorded expectation), ≥15 of 22 still fail:** compiler
  *fork* fully exonerated; mechanism is Darwin-side (system repair or
  fundraising interrupted) — favor candidate 2 (fenv/rounding/flush-to-
  zero state) + knife-edge amplification of the ≤1-ulp differences (T-c),
  discriminate next with a single-binary value trace (Mac vs Linux VM,
  same expressions, printed at contractor steps).
- **P-collapse, ≤3 of 22 fail:** Apple's clang-specific codegen/pipeline
  is implicated — surprising given T-d's gcc-22/22, would demand reconcilia-
  tion (faction co-causes or T-d's chain artifact), follow-up: shrink A/B.
- **4–14 (gap):** both mechanisms coexist; report the measured split and
  re-rank (LLVM-version-on-Mac vs Darwin-state probes).

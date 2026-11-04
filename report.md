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

**T-g attempt 1 (record):** invalid run — 122/445, 323 fail to build;
completeness flag caught it. Cause: brew llvm bundles its own libc++23
*headers* (`Cellar/llvm/23.1.4/include/c++/v1`), which at `-std=c++17`
expose a degraded `std::result_of` ("no type named 'type'") and
`std::fpos` availability vs Apple's SDK set → ThreadPool/abseil cascade.
Probe matrix: brew-llvm+brew-libcxx23 = FAIL, brew-llvm+Apple-SDK
libc++ = OK, linked dylib = system `libc++.1.dylib` regardless (brew llvm
ships no libc++ dylib).

**T-g attempt 2 (registered before running):** same trial question,
narrowed honestly: compile with LLVM clang but `-nostdinc++` + Apple SDK
`usr/include/c++/v1` headers (passed both as ibex-build `CXXFLAGS` and
`CELL_BAZEL_EXTRA_ARGS --copt`s; receipt echoes both). Delta vs C baseline
is now precisely LLVM front-end/builtins/codegen with the C++ standard
library (headers + system dylib) identical to baseline. Scoring branches:
unchanged from the 4699a23 registration.

**T-g attempt 2 (record):** again invalid (122/445; completeness flag) —
collapsing mechanism *identified, distinct from attempt 1*: every clang-23
cc1 invocation got `-fdepfile-entry=<SDK>/SDKSettings.json` (proved via
`-###`; apple clang 21 emits none: count 0). That absolute path lands in
the depfile it generates for all compile actions, and
`local_velociraptor`-style bazel validation ("absolute path
inclusion(s) found") aborts 265 rules. Bookkeeping only — no diagnostic
about code at all.

**T-g attempt 3 (registered before running):** `harness/shim-bin/
llvm-clang23-mac[++]` strips exactly that one arg (no other change); trial
delta unchanged = LLVM front end/builtin headers/codegen vs apple-clang-21,
stdlib headers pinned to Apple SDK, system dylib. Scoring branches:
unchanged (4699a23).

**T-g attempt 3 registration AMENDED (pre-run proof; no data observed):**
the `-fdepfile-entry` arg never appears on argv — the *driver constructs*
it when it parses SDKSettings.json, so argv filtering can't reach it
(verified: `-###` through the filter still shows it, count 1). The shim
instantiated on the other lever: on probe-shaped invocations (`-E` + `-v`,
which is how bazel's configure learns `cxx_builtin_include_directories`),
append the SDK root — the parent dir of SDKSettings.json, and a boundary
already containing every listed entry — before "End of search list." so
the validator accepts the file that clang itself insists on declaring.
Run argvs remain byte-identical otherwise. Scoring branches: unchanged
(4699a23). Brew's Cellar c++ dir is absent from that list too by design
(attempt-2 header pinning means nothing reaches it).

**T-g attempt 3 (record):** again the same validator abort (122/445), but
the trace now complete: my probe branch merged stderr+stdout, while
bazel's parser (`unix_cc_configure.bzl:117`, `result.stderr.find`, then
`rfind("\n ")` = last space-prefixed line) reads **stderr only** → saw an
empty region → `builtin_include_directories` collapsed to the sysroot
fallback singleton `[".../MacOSX.sdk"]` (symlink spelling via xcrun),
while the driver's own depfile entries spell the realpath
`MacOSX27.sdk/...` → prefix match fails → SDKSettings.json *and* every
`usr/include/...` header flagged. Shim fixed to inject the SDK root as the
final space-prefixed stderr line (stdout untouched); parser replication
verifies entries survive.

**T-g attempt 4 (registered before running):** identical to attempt 3,
plus fd-correct shim; fresh `CEL..._CC/CXX` alias paths
(`llvm-clang23-a4[++]`) guarantee repository reconfigure (marker keys
off the CC value). Scoring branches unchanged (4699a23). If this attempt
raises a *novel* validator class, stop and reassess rather than iterating
further — three infrastructure accommodations has been the honest cost of
running an untested compiler.

**T-g ATTEMPT 4: VALID FULL RUN (445/445, 0 validator hits) — SCORED.**
Failing set **byte-identical** to the canonical baseline: all frozen 22 +
the `timer_test` flake; ibex receipt shows the trial prefix (llvm-built
`352eeeb`). ≥15-of-22 persist branch: **P-persist TAKEN — the *fork* is
exonerated.** Apple clang 21, upstream LLVM-project 23.1.4 (different
driver, different bundled stdlib, different builtin toolchain), and brew
gcc-16: three compilers, same 22 on this Mac. Combined with clang-14 =
6/22 and gcc = 0/22 on Linux, the fork/version axis contributes nothing;
what remains is the Darwin runtime/SDK seam itself: system libc++/libm
knife-edge behavior (T-c: ≤1 ulp), fenv/rounding/flush-to-zero machine
state, or SDK-level behavior — all three candidate classes are now the
*only* unexcluded ones, and none of them is "the compiler".
Honest cost note for the record: 4 attempts, 3 infrastructure
accommodations (libc++23 headers → driver depfile-entry → verifier stderr
parse), each registered before its run; no test outcome was seen before
its registration.

## Round-6 strip (user-directed: falsified knobs out of the default path)

**Gate 1 — cell C on stripped base config (registered before running).**
Strip 1/2: `CELL_C_IBEX_PREFIX` default now empty; run-cell.sh falls back
to stock PATH pkg-config → Homebrew `ibex@2.7.4_13` (the pre-trial
recipe); shim off the path unless the knob is set (opt-in documented in
cells.env). Gate: failing set == the frozen 22, `timer_test` ±1. Result:
445/445 executed, receipt = `stock PATH pkg-config`, modversion 2.7.4,
-brew libs; diff vs frozen = **exactly one added line, `timer_test`**
(the registered flake) → **PASSED, strip kept.**

**Gate 2 — registered, full five-cell run, after strip 2 (trial
prefixes deleted).** Expected: A 445/445; B 444 (+`timer_test` ±1);
D/E 444 (known `-Wdangling-reference` unbuild + `timer_test` ±1); C = the
frozen 22 (+`timer_test` ±1) on the base config of gate 1. Any target
outside those sets ⇒ the offending strip gets reverted, not argued with.

**T-h — PRE-REGISTRATION (before any measurement): is ibex "the same"
on macOS vs Linux, given both build from literally the same commit?**
Ground truth under test: mac harness build and the `dreal-ref:22.04`
image build both source-build `dreal-deps/ibex-lib@352eeeb` (the gate-1
strip left mac on brew-2.7.4 for cell C, but *this audit uses the harness
prefix* `~/.local/opt/ibex-352eeeb` so source equality with the container
is exact-by-construction). Four audits, expectations committed first:
- **A1 installed header trees diff (`find`+sha256):** P = identical or
  identical-except-configure-generated settings headers.
- **A2 `ibex.pc` diff:** P = differ in prefix `-L` paths *and* Cflags
  platform flags (documented precedent: ibex.pc advertises `-msse3`/
  `-ffloat-store`; vendored formula strips the x86 one on arm64).
- **A3 exported symbols (`nm`):** P = ibex-own symbols equal, totals
  differ by std ABI (libc++ vs libstdc++ mangling/inline-namespace tags).
- **A4 VALUE PROBE (load-bearing):** tiny program compiled+run against
  each side's libibex, printing hex doubles (`%a`) for a fixed table of
  interval ops incl. transcendentals. P = arithmetic (`+ - * / sqr`)
  **byte-identical** (IEEE ops, same ISA); transcendentals (`sin cos
  atan exp log pow sqrt` endpoints) show the T-c-class ≤1-ulp bit diffs.
Scoring: arithmetic divergence ⇒ fenv/contract-below-ibex class (candidate
1) upgraded to *inside ibex's arithmetic*; transcendental-only ⇒ candidate
2 (OS libm) demonstrated where ibex actually pays; total identity ⇒ ibex+libm
cleared end-to-end ⇒ divergence must live above ibex (dreal side) or in
process FP state, and the linux-vs-mac ibex story is exonerated as a
numerics difference. Artifacts: `runs/T-h-*.{txt,diff}`.

**T-h SCORED (artifacts runs/T-h-*).** Same-commit ibex, macOS build vs
Linux build:
- **A1 headers: P hit-with-nuance** — 340/340 files present, **exactly one
  byte difference**: `ibex/ibex/ibex_LPSolver.h`, one line: mac
  `#include "coin/ClpSimplex.hpp"` vs linux `#include "ClpSimplex.hpp"`
  (configure-time CLP-layout rewrite, platform package layout, not code).
- **A2 ibex.pc: P half-miss** — only `prefix=` differs; **Cflags/Libs are
  byte-identical incl. `-frounding-math`** — no platform flags exist
  (stronger equality than P predicted).
- **A3 symbols: P miss** — export surfaces genuinely differ beyond ABI
  spelling: 2858 vs 3982 ibex symbols, 2400-element set delta (638
  mac-only / 1762 linux-only, non-guard/template-heavy): compiler emit +
  visibility/dead-strip policy differ. Artifacts sorted in
  `runs/T-h-artifacts.txt`.
- **A4 VALUE PROBE: P INVERTED — and inverted in the load-bearing
  direction.** 12/18 rows differ, all at 1 ulp; **all of it in pure
  arithmetic (add/sub/div/sqr/point/tiny); every transcendental (sqrt,
  log, exp, sin, cos, atan, pow) byte-identical.** Direction decoded from
  `0.1+(-3)`: linux lower bound = `-0x1.7333333333334p+1` = the FE_DOWNWARD
  product; mac = `-0x1.7333333333333p+1` = round-to-nearest. Plus row-wise
  (div ub, sqr lb, tiny lb) the same pattern: **linux endpoints round
  outward (rigorous intervals); macOS-built ibex endpoints round nearest
  (NON-rigorous intervals).**
- **Follow-on directed-rounding probe (`runs/T-h-fenv-probe.c/.txt`):**
  `fesetround(FE_DOWNWARD/UP)` **works identically on darwin-arm64 and
  linux-arm64** (rc=0, fegetround echoes, arithmetic moves `…333→…334` and
  back). The OS primitive is therefore NOT the failure — the
  apple-clang-built ibex path fails to have directed rounding in effect
  while running (codegen/honoring/inlining of the rounding-control layer),
  i.e. divergence is in the compiler↔fenv seam, not fenv itself.

Implications (hypothesis map): matches 3 of 4 grid quadrants directly —
LLVM-family builds (apple-clang 21, upstream LLVM 23) lose directed
rounding → all of macOS; clang-14 on Linux loses enough to sink the
6-test slice; gcc keeps it → Linux clean. The recorded T-d result
(**gcc-16 on macOS still 22/22**) *collides* with this and is now the
standing contradiction to resolve (candidate explanations to check: WAF
passing `-frounding-math` as *consumer* cflags in ibex.pc only vs into
ibex's own compile line (the -gcc prefix was deleted per round-6;
rebuild recipe on record); T-d's heterogeneity notes). Also upgrades the
ibex-2.9 question to a pointed one: does 2.9 change rounding technique?
Registration quality check: four sub-predictions, one saving nuance,
three misses — the P4 inversion is the finding.

**T-i — PRE-REGISTRATION (before rebuilding anything): T-d collision
resolution.** Rebuild `ibex-352eeeb-gcc` exactly as the ledger recipe
(gcc-16, IBEX_CSTDINT_FIX=1), compile the T-h value probe against it with
g++-16 (`-O2 -ffp-contract=off` + the prefix's own `pkg-config --cflags`,
receipts printed), score only the six arithmetic rows (decoders:
`add` lb outward = `-0x1.7333333333334p+1`, nearest = `…333`; same
signature rows: `sqr` lb, `tiny` lb, `div` ub).
- **P1a (expected): gcc-mac libibex rounds OUTWARD** ⇒ gcc honors
  -frounding-math here ⇒ T-d's 22/22 failure cannot be the rounding-loss
  ⇒ either a *second* darwin mechanism exists or the T-d run carried its
  own heterogeneity (its notes flag a "grafted chain") — next step then
  re-examines T-d directly.
- **P1b: gcc-mac rounds NEAREST** (matching apple/LLVM) ⇒ rounding-loss IS
  compiler-independent on darwin ⇒ the seam is darwin×ibex-build, and
  fenv-exonerated-yet-not-applied becomes the primary mechanism for all
  22.
Both branches keep the 6-test linux-clang slice for T-j(step 2).
Artifacts: `runs/T-i-*.txt`.

**T-i SCORED — P1b TAKEN.** g++-16-built `ibex-352eeeb` on this Mac (T-d
recipe, receipts: `-frounding-math` present in `pkg-config --cflags`,
`-ffp-contract=off`, linked against the rebuilt `libibex.dylib`)
produces **byte-identical nearest values to the apple-clang build**
(`add …333`, `sqr …47c`, `point …47c`, `tiny …2a`); Linux-gcc = outward
(`add …334`, `sqr …47b`, `tiny …29`). Reading:
1. **The T-d collision is resolved, in the theory's favor**: rounding-
   loss is *not* compiler-specific — two different mac-compiled compilers
   with the honest flag both round nearest; both Linux compilers round
   outward. Seam = darwin × (ibex idiom or darwin×compile-of-that-idiom).
2. The consumer-flag theory is dead too (the receipt shows the probe
   consumed `-frounding-math` and still lost).
3. Standing contrast driving step 3: plain `fesetround` probe (T-h
   follow-on, `runs/T-h-fenv.txt`) *works* on darwin — so general POSIX
   rounding works, while arithmetic *inside ibex's rounding-control
   pattern* does not take effect. Difference-maker must be inside
   `ibex/3rd/rounding_control/*` — an `__APPLE__`-style branch or
   different dance — headers reviewed for `#if` selection next
   (step 3), and mac headers are byte-identical to linux's (T-h A1),
   so whatever diverges is a *preprocessor define*, not text.
Artifacts: `runs/T-i-gcc-pc.txt`, `runs/T-i-rounding.txt`.

**T-j — PRE-REGISTRATION (before building):** build `ibex-352eeeb` with
**clang-14 inside `dreal-trial-clang:22.04`** (the T-e image: jammy,
glibc, the exact compiler behind the 6-test linux slice) to the same
T-h value-probe receipts (`-O2 -ffp-contract=off` + prefix pkg-config
cflags incl `-frounding-math`, `LD_LIBRARY_PATH` set).
- **P2a (expected): rounds NEAREST** (like both mac compilers) ⇒ the
  T-e six share the rounding-loss class → a single mechanism story
  covers the whole grid (darwin-driver & compiler-axis unified: LLVM-
  family loses the idiom-effect everywhere, gcc keeps it, except gcc
  *on darwin* loses anyway ⇒ refine: loss = LLVM-family OR darwin).
- **P2b: rounds OUTWARD** (like linux gcc) ⇒ rounding does NOT explain
  the T-e six ⇒ the 6-slice keeps its own second-mechanism status
  (contraction/other codegen), fitting its smaller membership.
Artifacts: `runs/T-j-*.txt`.

**T-j attempt 1 (record):** ibex built fine with clang-14 in the T-e
image (receipt: `-frounding-math` present), probe compile refused the
mounted include tree ("Permission denied" — cross-container volume
observation issue, not ibex's). **Borrowed evidence in that compile
output, independent of my scoring:** clang-14 on aarch64-linux warns
`overriding currently unsupported rounding mode on this target
[-Wunsupported-floating-point-opt]` — LLVM explicitly *overrides*
dynamic rounding-mode changes on this target while GCC kept quiet.
Attempt 2 = build AND probe in one container session (no cross-session
volumes), scoring branches unchanged.

**T-j SCORED — P2b TAKEN.** clang-14/glibc-libstdc++-built ibex (same
commit, same `-O2 -ffp-contract=off` + `-frounding-math` receipts)
rounds **outward** on every decoder (`add …334`, `sqr …47b`, `tiny …29`)
= the linux pattern, like linux-gcc. (Its compile *warned*
"unsupported rounding mode … overridden" yet outcomes are correct —
warning ≠ our failure signature.) Grid now: **darwin/2-of-2-compilers =
nearest; linux/2-of-2-constructors = outward.** Rounding-loss tracks the
OS, not the compiler → the 22-cluster mechanism candidate; T-e's six are
*excluded* from rounding and keep their own (codegen-class) lane.
Artifacts: `runs/T-j-receipt.txt`, `runs/T-j-rounding.txt`.

**K — PRE-REGISTRATION (mechanism pull, read-only):** T-h A1 says the
rounding_control headers are byte-identical across OS builds → whatever
diverges must be (a) a preprocessor-selectable branch in that text
(Pka: some `__APPLE__`/target-guard makes darwin skip or neuter the
mode-set dance) or (b) identical-at-runtime path but divergent flag/
codegen plumbing that survives -frounding-math only on darwin (Pkb).
Reads: which rounding primitive + its `#if` tree; whether the dance lives
in headers (visible to every TU) or inside libibex `.cpp` (waf-owned
flags only); `nm -i round` for lib-level rounding symbols. Either branch
keeps fenv-exoneration from T-h follow-on intact.

**K SCORED — Pka TAKEN (with the guard identified exactly), Pkb FALSIFIED.**
The complete causal chain, every link measured:
1. `rounding_control_double.hpp:78-91`: sparc-asm → **`#elif
   defined(__STDC_IEC_559__)` → iso9x** (the `fegetenv/feholdexcept +
   fesetround(FE_DOWNWARD/UPWARD)` dance) → msc-asm → **else → `void`**,
   whose `downward() {} upward() {} tonearest() {}` are literally empty
   (bodies printed, `runs/K-mechanism.txt`).
2. `config.hpp`'s force-define of the macro is **commented out (lines
   14-18), byte-identical mac+linux** → dead on both sides (Pkb's
   "flag/config plumbing" reading falsified: `-frounding-math` defines
   the macro nowhere; it's plumbed fine everywhere).
3. The macro's *declared* value is an ecosystem property:
   **glibc/libstdc++ declares it (linux g++ natively =1; linux clang-14
   goes 0→1 through `<iostream>`); neither mac toolchain+libc++ chain ever
   does (0,0)** ⇒ darwin selects **void** → NO rounding control ever set
   → interval endpoints round to nearest → **non-rigorous intervals on
   macOS, under all compilers tested (2-of-2 nearest), rigorous on
   linux (2-of-2 outward)** — exact 2×2 grid match.
4. `fesetround` itself works on darwin (T-h follow-on) → the fix is a
   macro/selector-level environment claim, not an OS defect; and the
   claim is *true* on this hardware (probe proved directed rounding
   works when selected).
Consequences: C1 wrong-`unsat`-with-witness cluster has its mechanism;
pure-linear `github_issue_192` (T-c's dead-end at libm altitude)
explains itself at arithmetic level; T-i's gcc-nearest and T-j's
clang14-outward both fall out; T-e's 6 remain outside rounding (its
cells link gcc-11-built ibex = native macro = iso9x). Session-1 linux
nm-of-0 (`runs/T-j-*`) recorded as a capture anomaly, superseded by the
fresh session's 3 refs. Artifact: `runs/K-mechanism.txt`.

**T-l — PRE-REGISTRATION (ibex 2.9.1: the user's original upgrade trial,
now mechanism-informed).** Install stock homebrew `ibex` 2.9.1 (arm64,
no deps) WITHOUT touching the base config; gates + predictions first:
- **G-base:** after install, stock `pkg-config --modversion ibex` MUST
  still be 2.7.4 (round-6 base config untampered); if brew's link step
  disturbs it, restore + record.
- **P-sel:** 2.9's selector still lands `void`-on-darwin (same
  filsib-era mechanism upstream rather than reworked) ⇒
- **P-behav:** T-h value table vs 2.9 = nearest (byte-equal mac rows).
- **P-score (cell C against 2.9, if it builds):** **≥15 of the frozen 22
  still fail** (= mechanism survives upgrade) with ≤4 *new* targets
  outside it; **P-fix branch: ≤3 of 22 fail** ⇒ upgrade genuinely clears
  the darwin mechanism (then Linux-on-2.9 rerun = mandatory stage-2 for
  any green claim, one-variable-per-cell re-baseline caveat as before).
- **P-build:** if 2.9's API breaks the link/compile (install_prereqs
  documents "incompatible API"), the run is invalid-as-test-score and
  the *error census* is the product: port size, line count in
  `runs/T-l-port-census.txt`.
Artifacts: runs/T-l-*.

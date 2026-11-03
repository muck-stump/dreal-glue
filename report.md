# A/B report: dreal4 base vs `modernize-macos` in the reference container

**Verdict: no behavioural drift.** The 13 modernization commits change
nothing observable: cells A and B executed the *identical 445 test targets*
and both passed **445/445**. `comm -3 runs/failed.A.txt runs/failed.B.txt`
is empty (both files are 0 bytes).

## Matrix — results

| cell | code | environment | state |
|---|---|---|---|
| A | base `f93bdcc26b62abdcc30ad7de6046729bb48016b9` | reference container | **measured: 445/445 pass** (bazel rc 0) |
| B | `e6d31b485d3ed828725e2c093c610031def17a3c` (`modernize-macos` tip) | reference container | **measured: 445/445 pass** (bazel rc 0) |
| C | branch `e6d31b4` | this Mac (macOS, Apple Silicon) | measured: 445, 303 pass / 142 fail |
| D | base `f93bdcc` | this Mac | does not configure/build (build-level; why the modernization exists) |

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

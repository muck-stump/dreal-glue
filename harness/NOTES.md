# harness/NOTES.md — live progress log

Dev-thread scratch for cold starts; conclusions get folded out of here into
`report.md` and `dreal4/README.md` as documentation commits (per the glue
repo's "tooling out, conclusions in" rule).

## Goal (short)

Cells A/B in one shared Ubuntu 22.04 podman image:

- A = `f93bdcc26b62abdcc30ad7de6046729bb48016b9` (original, pre-modernization)
- B = `e6d31b485d3ed828725e2c093c610031def17a3c` (modernize-macos tip = submodule pin)

Each cell: `bazel test //...`, then the sorted list of failing target labels.
Verdict: `comm -3 runs/failed.A.txt runs/failed.B.txt` must be **empty** —
anything only on B's side is behavioral drift we introduced.

## Environment decisions and why

- **One image for both cells** (`dreal-ref:22.04`): apt resolves exactly once
  at image-build time; the two cells *cannot* drift package-wise. (Q from the
  maintainer: "same Ubuntu for both feels spooky, package manager pins" —
  agreed on the pins worry: apt has no lockfile. The pin is the single image
  ID + a `dpkg -l` manifest recorded in the report. Different Ubuntu releases
  for A vs B would confound code with environment, killing the A/B.)
- **arm64 native**: podman 6.1.4 offers no `--rosetta` on machine init, so the
  amd64 tiebreaker arch is out of scope; arm64 matches cell C anyway.
- **Bazel 7.0.0**: upstream publishes **no arm64 `.deb`** (checked GitHub
  releases *and* releases.bazel.build — README's caveat, but stronger than
  worded: there is no filename to swap). `install-bazel.sh` installs the
  official self-contained `bazel-7.0.0-linux-arm64`, sha256-pinned from the
  release's `.sha256` asset; the amd64 path keeps upstream's exact deb+sha
  from `install_prereqs.sh`. Container-side only — checkouts stay pristine.
- **`install_prereqs.sh` runs verbatim** for the apt deps; it is
  byte-identical between the two pins (verified: between base and tip only
  `.bazelrc` and `setup/mac/*` changed). One harness-side deletion:
  `libibex-dev` (see below).

## ibex: why the container source-builds it, and from what

- ppa:dreal/dreal ships `libibex-dev` for **amd64 only**: the PPA's
  `dists/jammy/main/binary-arm64/Packages` index is **empty (20 bytes)**,
  amd64 has it. So on arm64 the apt package cannot exist → README's
  anticipated fallback: build ibex from source (image gets
  `sed -i '/^libibex-dev$/d'` on its *copy* of the prereq script).
- **Which source = the PPA's own source.** The amd64 package version is
  `2.7.4.20220710…git352eeeb2345fb2b7a7ec248b44770d8cdc4a5d67~22.04`, i.e.
  dreal-deps/ibex-lib **@352eeeb** — also what `Dockerfile.amazonlinux`
  builds from source into **`/opt/libibex/2.7.4`**, the exact prefix
  `dreal/workspace.bzl` probes on Linux. So arm64 gets the reference
  amd64's own ibex source at the path dreal already expects.
- **cell C differs**: its mac formula pins tag `ibex-2.7.4_13` = commit
  `26eeeaa` (2021-08-26), a *different snapshot* of the 2.7.4 line
  (trees differ across plugins/). Same version string, not same tree →
  record under B-vs-C attribution (never affects A-vs-B: one image).
- arm64 details, all verified: configure probes `-frounding-math` and
  `-ffloat-store` compile on gcc-11/aarch64; `-msse3` fails but the wscript
  guards it (`mandatory=False` → sse2 → plain fallbacks); installed
  `ibex.pc` has `-msse3 -ffloat-store` baked in from `ibex.pc.in` → stripped
  post-install (**identical to cell C's formula "Patch 3"**); system clp
  found via `/usr/lib/aarch64-linux-gnu/pkgconfig/clp.pc` (no bundled-Clp
  fallback); bundled `filibsrc-3.0.2.2` builds via configure+**`make`**
  (apt list lacks `make` → harness installs it, as amazonlinux's yum list
  does); `waf` is already `python3` at this commit (no shebang patch).

## Root cause: image build failure (solved)

Symptom (failed twice): inside `podman build`,
`add-apt-repository ppa:dreal/dreal` →
`gpg: error running '/usr/bin/gpg-agent': probably not installed` →
`can't connect to the agent: Configuration error` → PPA key import fails.

Diagnosis trail: NOT build-vs-run (a minimal `podman build` repro passed);
NOT missing `/root/.gnupg` (disproved, both with/without it pass in `run`).
Real cause: the script's `apt-get install --no-install-recommends
software-properties-common` skips `gpg-agent` on 22.04. Confirmed by matrix:
recommends = pass, `--no-install-recommends` = fail with "probably not
installed". Fix: Containerfile pre-installs `gpg-agent` before running the
upstream script (upstream CI runners ship it already → same effective env).

## Parallel plan (approved by maintainer)

Both cells detached at once from the one image; machine budget is shared
(8 CPU / 12 GiB / 60 GiB total), so per cell:
`--jobs=4 --local_cpu_resources=4 --local_ram_resources=6000
--host_jvm_args=-Xmx1500m`. Volumes per cell: `dreal-cell-{A,B}-src`
(`git archive` tar of the pinned commit = bit-for-bit tree, no `.git`, no
worktree dirt) and `dreal-cell-{A,B}-bazel` (own cache/output base, per
README: one cache per checkout). Expect both done in ~1.5–2 h wall clock.

## How to use

```bash
podman build -f harness/Containerfile -t dreal-ref:22.04 .  # once
harness/run-cell.sh A                                       # ...then B, or both at once
podman logs -f dreal-cell-A                                 # watch
harness/collect.sh A ; harness/collect.sh B                # → runs/failed.{A,B}.txt
comm -3 runs/failed.A.txt runs/failed.B.txt                 # drift, if any
```

Per-run artifacts: `runs/failed.<cell>.txt` (committed),
`runs/{bazel-test.<cell>.log,flaky.<cell>.txt,exit-code.<cell>.txt}` (local
only, gitignored). Oracle: `PASSED/FAILED/TIMEOUT/NO STATUS` per-target lines
in the bazel test summary table (`NO STATUS` = couldn't build under `-k`).

## Run history (why run 1 is discarded)

- **Round 1 — INVALID.** Both cells reported `Executed 186 out of 186
  tests` and rc 1: `tools/gmp_repository.bzl` hardcodes the x86 gmp.h
  tuple → fetch failure → loading-phase errors silently dropped ~259
  targets (`Executed N out of M` counts only what survived loading), and
  the fail-parser additionally matched mid-log gtest lines
  (`[  FAILED  ]`, ` 1 FAILED TEST`) as bogus labels. Fixed: image gets a
  gmp.h symlink (Fedora branch of the rule), parser anchors on `$1 ~ /^\/\//`,
  driver records `completeness.<cell>.txt` so an empty failed-list cannot
  again hide a partial run, `--cache_test_results=no` forces real replay.
- **Round 2 — VALID**: 445/445 in both, `comm -3` empty. Cell B's
  `timer_test` failed once in round 1 and passed in round 2 (identical
  sources between pins) → flake, both rounds recorded honestly.

## Round 2 — OS-modernisation cells E and F (running)

Question: B's code on a current distribution — did OS modernisation in
general move any test result? One variable per cell.

- **E** = ubuntu:24.04 (noble): gcc 13.3, Python 3.12.3, gmp 6.3.0,
  clp 1.17.9, nlopt 2.7.1
- **F** = fedora:43: gcc 15.3, Python 3.14.8, gmp 6.3.0, clp 1.17.10,
  nlopt 2.10.0
- both: commit `e6d31b4` (= cell B), ibex `352eeeb` source-built at
  /opt/libibex/2.7.4, Bazel 7.0.0 sha-pinned, same driver, batches of
  2 at the measured 4 CPU / 6 GiB budget
- harness change: `cells.env` now holds commit × image × recipe per cell
  (accessors `cell_commit/image/recipe`, `CELLS` list), run-cell/collect
  are cell-agnostic and record a per-cell `runs/env-manifest.<cell>.txt`,
  and **`harness/run-all.sh <cells…>` is the single entry point**
  (build-if-missing → run batch → collect → `comm -3` vs cell B).

### Distro facts probed in the base images before writing any recipe

- Fedora names for the 22.04 list: `coin-or-Clp-devel` ↔ coinor-libclp-dev
  (verified: `dnf provides '*/clp.pc'` → /usr/lib64/pkgconfig/clp.pc,
  1.17.10), `NLopt-devel` ↔ libnlopt-cxx-dev (capital letters; **nlopt
  2.10.0** vs reference 2.7.1), gmp-devel ships /usr/include/gmp.h =
  exactly the gmp rule's Fedora branch → no symlink fix needed; flex.
  python3.10 IS archived (reason for the WAF choice below).
- noble: `python3-distutils` does not exist; ppa:dreal/dreal has no noble
  release; and **no python3.10/3.11 in the archive at all**.
- Neither distro has an ibex package (Ubuntu's came from the PPA) →
  source build as always.

### Container-side accommodations (harness-only; captured here, results in report.md)

1. noble package list = upstream's 22.04 heredoc verbatim minus
   `python3-distutils` and minus the `add-apt-repository` PPA step
   (ibex source-built). Dropping the PPA step also removes the gpg-agent
   trap the 22.04 recipe needs a pre-install for.
2. **ca-certificates**: the trimmed apt list (--no-install-recommends)
   lost wget's CA bundle → wget fails rc=5 "SSL certificate problem" on
   codeload.github.com; the reference image only had it transitively via
   the PPA tooling. Added explicitly (build #2 died exactly there).
3. **gmp.h symlink**: needed on both Ubuntu images (the
   tools/gmp_repository.bzl multiarch gap); Fedora needs none — the
   recipe only guards `test -e /usr/include/gmp.h` so a future change
   fails the image loudly rather than silently dropping ~259 targets
   (the round-1 lesson).
4. **ibex vs modern libstdc++**: GCC ≥ 13 stopped transitively including
   <cstdint>, and ibex 2.7.4 (2022) uses uint32_t without including it.
   Measured: noble/gcc-13 errors in ibex_Cov.h + ibex_Cov.cpp +
   ibex_CovIBUList.cpp; fedora/gcc-15 in ibex_Cov.h +
   ibex_CovSolverData.cpp (all cascade off ibex_Cov.h:106).
   Fix: opt-in `IBEX_CSTDINT_FIX=1` in install-ibex.sh prepends
   `#include <cstdint>` to the two hot spots. The reference recipe does
   NOT set it → 22.04 builds exactly what it always did (gcc-11 doesn't
   need it; proven to build clean under both new compilers afterwards).
5. **ibex's build tool vs Python ≥ 3.11**, three separate walls:
   waf 2.0.12 does `import imp` (gone in 3.12) and `open(…, 'rU')`
   (gone in 3.11); ibex's wscript does `from distutils.version import
   LooseVersion` (gone in 3.12). Fix = give the *build tool* a CPython
   3.10 via `WAF_PY` (install-ibex.sh), so A/B/E/F are built by the same
   interpreter version while each cell's tests still run its distro's
   stock Python — the variable under measurement:
   - F: `dnf install python3.10` (native archive package);
   - E: noble packages no old CPython → multi-stage recipe
     `FROM ubuntu:22.04 AS jammy-py` grafts jammy's python3.10 +
     stdlib (binary needs only libexpat1 beyond base — ldd-checked).
   Dead ends, recorded so nobody retries them: pypy3 (3.9, has imp, but
   waf's subprocess layer dies with a pickle error); an `imp` shim on
   PYTHONPATH + sed-ing the extracted waflib ('rU'→'r') — clears two
   walls, then hits distutils…

### Predictions (to be scored in report.md — written before results)

- **E**: 119 cpplints PASS (sre_compile exists until Python 3.13) —
  i.e. cell C's cpplint class should NOT reproduce on noble; the 21
  unsat-cluster + get_value_01 should pass (Linux/g++/ibex@352eeeb =
  the reference's own stack); timer_test may flake. Overall ≈ 445/445
  modulo gcc-13 `-Werror` surprises.
- **F**: the 119 cpplint failures SHOULD reproduce (Python 3.14 ≥ 3.13,
  same class as cell C) — that would localise the class to *Python
  version*, not *macOS*. Everything else expected green. Watch items:
  nlopt 2.10.0 vs 2.7.1 and clp 1.17.10 vs 1.17.5 (optimization tests
  ⇒ attribution: system-library version = environment), gcc-15 -Werror
  on dreal's own sources (a build-level failure would be a cell-D-class
  outcome — incomplete-run detection lives in completeness.<cell>.txt).
- Scoring intent: if E is fully green and F fails only cpplints, then OS
  modernisation moves nothing solver-relevant, and cell C's 142 stay
  fully macOS-host-attributed.

### Scored (results: report.md → "Round 2")

- E = 444/445, F = 443/445; target sets 445 = 445 = 445 with empty
  `comm -3` of the label lists (B↔E, B↔F). Behavioural diff: **none**.
- The anticipated gcc `-Werror` surprise arrived — as exactly one build
  failure in both cells: `-Wdangling-reference` false positive on
  `ibex::ExprSymbol::new_()` (a heap-object factory) at
  contractor_ibex_fwdbwd_test.cc:134-136; new warning in GCC 13, so it
  needs an explicit new-distro toolchain to appear at all.
- **cpplint-on-F prediction wrong**: 119/119 pass on Python 3.14.8 —
  `sre_compile` is only *deprecated* there (import verified in both
  images); cell C's host 3.15 is where it's gone. Correct "removed in
  Python ≥3.13" to "≥3.15" in dreal4/README during the docs round; the
  class is host-python, now confirmed not-distro-level.
- unsat-21 + get_value_01 pass in E and F ✓ — the mac-only cluster also
  survives nlopt 2.10 / clp 1.17.10 / gcc-15.
- `timer_test` flaked in F only ✓.
- Net: one build-level compiler-warning delta + one timing flake, zero
  behavioural drift → cell C's 142 remain fully mac-attributed.

## Status

- [x] podman installed + machine created (6.1.4, applehv, arm64, 8/12288/60,
      no `--rosetta` option in this version)
- [x] harness written (`Containerfile`, `cells.env`, `install-bazel.sh`,
      `install-ibex.sh`, `in-container-test.sh`, `run-cell.sh`, `collect.sh`)
- [x] gpg-agent root cause, fix in Containerfile (container-side)
- [x] reference image `dreal-ref:22.04` built — final id
      `0c0567ed3fc1ec3283873645964e1ccae668eb43df9c1faa9fdd8dfaef1fd410`
      (gpg-agent fix, source ibex, `make`+`wget`, sha-pinned bazel 7.0.0
      arm64, gmp.h symlink)
- [x] cells A + B run in parallel (rounds 1 invalid / 2 valid — see run
      history above): container `dreal-cell-A/-B`, volumes
      `dreal-cell-{A,B}-{src,bazel}`
- [x] `runs/failed.{A,B}.txt` collected — both **empty**; completeness:
      445/445 executed, no loading errors; identical target sets
- [x] `report.md`: empty `comm -3` diff + attribution; image ID +
      `dpkg -l` manifest in `runs/env-manifest.txt`; all four cell-C
      predictions scored confirmed (119 cpplint / 21 unsat-cluster /
      `get_value_01` env-caused, `timer_test` flaky)
- [ ] conclusions folded into `dreal4/README.md` as docs commits
      *(maintainer step — submodule intentionally untouched so far)*
- [x] round 2 (cells E/F, OS-modernisation): images built
      (`dreal-ref:24.04` = 3e25babda5a7…, `dreal-ref:fedora-43` =
      1066b7d27b9e…) and both cells run via `run-all.sh E F`:
      E 444/445, F 443/445, behavioural drift vs B = none (see the
      Scored block above and report.md)
- [ ] optional follow-up round: fix `gmp_repository.bzl` arch probe as a
      normal dreal4 commit → new pin → fresh A'/B' pair

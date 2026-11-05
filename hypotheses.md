# Hypotheses ledger: why does cell C answer `unsat` where every Linux cell answers `delta-sat`?

The investigation this workspace exists for, kept as an append-only ledger
of *trials*: hypothesis → intervention → effect on the tests → verdict →
evidence. Predictions get pre-registered in [`report.md`](report.md) before
runs exist (house rule); this file is where the cross-round picture lives.
Raw artifacts: `runs/`, `runs/SUMMARY.md` (live view: `harness/summary.sh`).

**The phenomenon.** Cell C (modernized code on this Mac) fails 22 of 445
targets; every other cell (A, B, D, E — A/B reference container, Ubuntu
24.04, Fedora 43) fails at most 1–2, all attributable to known categories.
The 22: expected `delta-sat`, got `unsat`, clustered in the ∃∀/Minimize/
`exist_forall_*`/`ea_*`/`.dr cost:` paths, plus `get_value_01` (one-ULP
model diff). Master table by erratum class: see "step 1" classification
below and `report.md`.

---

## Trial ledger

| # | trial (hypothesis tested) | what we did | effect on the tests | verdict |
|---|---|---|---|---|
| 1 | The 13 macOS-modernization commits change behavior? | Built `f93bdcc` vs `e6d31b4` in the *same* reference container (cells A, B) | **none** — 445/445 each, `comm -3` empty | **No drift.** The modernization itself is cleared (report.md round 1) |
| 2 | Newer Linux OS/toolchains (the "modern OS" worry)? | Cells D/E: Ubuntu 24.04 (gcc 13, py 3.12, gmp 6.3) and Fedora 43 (gcc 15, py 3.14, nlopt 2.10); same commit, same ibex, same bazel | **none behavioral** — only 1 target unbuildable (GCC≥13 `-Wdangling-reference` under `-Werror`, both) + the known `timer_test` flake once | **Exonerated**: newer glibc/gcc/python on Linux never produce the cluster. The OS *scale* is fine; only this Mac is special (report.md round 2) |
| 3 | Cell C's 119 cpplint failures = host Python 3.15 (cpplint's vendored `sre_compile` removed in 3.15)? | `brew install python@3.14`; dreal4 `.bazelrc`: `build:macos --repo_env=PYTHON_BIN_PATH=/opt/homebrew/bin/python3.14`; committed under test **as part of C's code** (`6a0c0cc`, wording `1ea8627`, docs `f37a1c1`) | **445 → 423 pass: exactly 119 flip to pass, zero new failures**; remaining 22 = the C-native non-Python set | **Worked** — Python 3.14 is now cell C's recipe, and the interpreter bucket is fully explained. Verification trap: `bazel query` does *not* apply `build:` sections; read `external/local_config_python/BUILD` → `interpreter_path` instead (report.md round 3) |
| 4 | The cluster = wrong ibex *source* (Mac: Homebrew `ibex@2.7.4 = 2.7.4_13` → commit `26eeeaa`, 2021-10; every Linux cell: source-built `dreal-deps/ibex-lib@352eeeb`, 2022-10) | Built `352eeeb` on the Mac through the pinned `harness/install-ibex.sh` (`PREFIX=~/.local/opt/ibex-352eeeb`), resolved via `harness/shim-bin/pkg-config` (prepend to PATH for cell C only + bazel shutdown; brew and the checkout untouched); 3 full cell C re-runs | **0 of 22 flip**, byte-identical cluster each run (`timer_test` flaked in 1 of 3 — its own category) | **Falsified** — the ibex source commit is not the mechanism (report.md round 4; prediction pre-registered ≥19/22 in `8c1f514`, measured 0; linkage triple-verified: fetched `@ibex` BUILD bakes our prefix, cflags byte-match modulo prefix, `otool -L` → our dylib; `runs/ibex.C.txt`). The `26eeeaa..352eeeb` pin gap itself = **2 commits, 27 files, +32/−29 — all `wscript`/`waf`/python3-port, zero numerical sources** (see footnote) |
| 5 | *(analysis, not intervention)* are the 22 one failure mode or several? | Read all 22 inputs/expected files; margin/mechanism classification: **C1** exactly-sat with witnessed extremum (14, incl. pure-linear `github_issue_192`, margin 5.8e6) → `unsat` *not licensed*; **mixed C1/C2** suite targets (3: `//dreal/api:cav18_*`, python `api_test`); **C2** exactly-unsat-but-δ-sat — strict-open feasible set, unattained infimum ⇒ **both answers legal** (2: `constrained_opt_rosenbrock_{cubic,disk}`); **C3** undecidable by eye (2: `ea_01`, `github_issue_201`); **C4** value-drift, no flip (1: `get_value_01`) | n/a | The 22 = **not one thing**: at most 20 are a solver defect on this Mac, 2 are legally any-answer, 1 isn't a flip at all. This rubric scores every future trial below |

Incident log (harness, not hypothesis): the letter-rename vs volume-name
collision, and the two parser blind spots, live in `harness/NOTES.md`.

**Footnote — trial 4's free extra bolt (no run):** the entire gap between
the two pins was read directly instead of being run:
`26eeeaa..352eeeb` contains exactly **2 commits / 27 files / +32−29
lines** — `python2.7 => python3` (wscript/waf/`3rd/patch.py` port) and
`fix(plugins/lp_lib_clp/wscript): Use find_program for CLP`. Not one
interval/contractor/solver/numerical source file changes. Consequences:
on macOS both pins cluster, so no brew-formula patch set can be necessary
either; and the reverse arm (formerly T-f, "Linux cells on `26eeeaa`") is
**dropped — maintainer call, sealed by this diff**: it is predicted to
equal the already-observed linux+`352eeeb` quadrant by construction,
nobody realistically runs linux+`26eeeaa` (dreal's PPA ships
`352eeeb`), and it cannot change any action queued in T-a..T-e.
Revival conditions: (a) writing platform-general ibex claims back into
`dreal4/README.md` — re-cite this footnote instead of running; (b) *every*
toolchain trial T-b..T-e returns null — then all untested axes return to
the table (the pin axis stays dead regardless).

---

## What the ledger has excluded so far (the hypothesis space, narrowed)

- ✗ dreal4's own git history (trial 1) — same source answers identically on Linux.
- ✗ *new-ness* of Linux components: gcc 11→15, Python 3.12→3.14, glibc 2.35→41, gmp/nlopt bumps (trial 2) — none reproduce it.
- ✗ host Python on Mac (trial 3) — solved its bucket exactly.
- ✗ ibex source commit (trial 4) — swap verified in, zero effect.
- ✗ CPU architecture — **held constant by construction**: all five cells are arm64 (containers run arm64-native in the podman machine; C is bare Apple Silicon).
- ⟹ Remaining axis that *only* C changes: **Apple clang 21 vs gcc, Darwin libm vs glibc, and the macOS-specific `.bazelrc` build flags** — i.e. how the identical sources are translated and what they link against, on this machine.

Two facts that *rank* the remaining suspects rather than just list them:

- **`github_issue_192` is pure linear arithmetic** — no `sin/exp/sqrt`, no
  quantifiers, no cost directive (its asserts satisfy at ≈1e6 margin by
  hand). A libm-transcendental explanation cannot cover it; something in
  the compiled core (interval/contractor arithmetic, compiler codegen,
  contraction, or a contract that clang evaluates differently) can.
- **All three sub-families** (C1 linear, C1 nonlinear-∃∀, C2/C4) move
  together run-to-run — so if a trial flips, expect it to flip most of the
  20 non-C2 targets at once (this is the scoring rubric for next trials).

---

## Next trials (**executed — see “Round 5, executed” at the end**; table kept as the pre-run plan)

Each was pre-registered in `report.md` before its run, then executed and
scored; verdicts and the cross-experiment outcome grid live in the
“Round 5 — executed & scored” section at the bottom of this file.

| # | trial | isolates | cost | prediction slot (register before running) |
|---|---|---|---|---|
| T-a | **Flag inventory diff**: dump the compile command for one shared TU on C vs D (`bazel aquery`/`--subcommands`) and diff `-f*` sets | concrete discovery of what Apple's build chain adds/changes (`-ffp-contract`, fortify, ISA flags) before spending a run | minutes | _:_ |
| T-b | Rebuild+rerun C with **`-ffp-contract=off`** (runner-passed extra copt; code untouched) | FMA/contraction codegen in interval comparisons = H1 (leading) | 1 C run | _:_ |
| T-c | Dual-machine **value probe**: same small program/fixture printing `sin/exp/pow/interval` results on C's machine and inside cell D's image (glibc) at cluster-relevant inputs | Darwin vs glibc libm divergence *magnitude* = H2 (cheap diagnostic — ordered after T-b because of `github_issue_192`) | minutes | _:_ |
| T-d | C rebuilt with **brew gcc** (full toolchain swap inside the same OS: ibex + dreal via `CC/CXX`) | gcc-vs-Apple-clang codegen, OS held = darwin = H3 | ~1 C run + ibex rebuild | _:_ |
| T-e | **clang inside a Linux container** (new image variant; same clang family, glibc/libm held) | clang-family vs darwin side, OS held = linux = H4 | 1 image + 1 run | _:_ |

(T-f, the reverse arm — Linux cells against `26eeeaa` — was dropped: see
trial-4 footnote.)

Reading of T-b/T-d outcomes against trial 5's rubric: a *majority of the
C1/C3 set flips* = culprit confirmed at that layer (the 2 C2 targets may
legally sit still, `get_value_01` and `timer_test` excluded from scoring).
*Zero flips again* = move down the table; by T-d/T-e either clang-side or
darwin-side must light up — they cannot both stay dark (trial 2 already
dark on the gcc/linux side).

## Round 5 — executed & scored (the trials above, as run)

| # | intervention (one Δ vs control) | measured result | verdict vs pre-registration |
|---|---|---|---|
| T-a | none — read the two toolchains' actual CppCompile argvs + default probes (`runs/T-a-compile-flags.txt`) | explicit FP flags: **identical** (only diagnostics/defines differ); defaults: apple clang fuses same-expression only, gcc fuses cross-statement too, both at `-O2` | discovery: the differentiator lives in *defaults vendor-side* or *runtime*, not in dreal's own copts; H1's prior lowered honestly before T-b |
| T-b | `-ffp-contract=off` on dreal (CLI copt, echoed receipt) **and** harness-ibex rebuild | **0/22 flip** — failed set byte-identical (+timer flake only) | **H1 falsified** (registered ≤3-branch hit). Contraction usage in this Mac's translation is not the mechanism |
| T-c | dual-machine libm probe, 420 points incl. cluster-relevant arguments (`runs/T-c-libm-probe.txt`) | 12/420 differ at all; **max 1 ulp** (`atan`) | **registered ≤4-ulp bound held**. Darwin-vs-glibc libm divergence real but tiny — excluded as a table-level explanation (and `github_issue_192`'s margin is ~5.8e6), still live only where knife-edge windows coincide with Darwin |
| T-d | same Mac, brew **gcc-16** for both halves (5 attempts: `-mmacos-version-min` dialect → `@params` leak → gcc-doesn't-link-libstdc++ → brew gmpxx libc++ ABI → gcc-built gmp-6.3.0 trial prefix; all in `harness/shim-bin/gcc-16-compat`) | valid run at attempt 5 (444/445; 1 unbuild = known `-Wdangling-referenence`, matching D/E exactly): **22/22 still fail** | **persist-branch hit**: compiler vendor exonerated on Darwin; mechanism lives on the Darwin side. 6 gcc-specific side-failures recorded (cds×2, python×3, +flake) as artifacts of the grafted libstdc++ link chain. Note: `-Wdangling-reference` reproducing under gcc-16/mac at `contractor_ibex_fwdbwd_test.cc:134-136` **agrees** with cells D/E — that wire is compiler-portability, not cluster |
| T-e | reference image (cell B's env) + **clang-14** delta, shimmed only `-Wno-deprecated-builtins` (dreal's `.bazelrc:159` copt: fatal under clang `-Wunknown-warning-option -Werror`, silently ignored by gcc — why no gcc cell ever saw it) | valid run (445/445 executed): **7 fails = 6/22 of the mac cluster** (`eav18_with`, `eav18_without`, `ea_beale`, `exist_forall_06`, `get_value_01`, `minimize_03`) + `timer_test` flake | **registered “absent, ≤2” branch MISSED, in the gap short of ≥10** — the gap is the finding (matrix below) |

### Outcome grid — cluster reproduction (out of the frozen 22)

| runtime ↓ / compiler → | gcc | clang |
|---|---|---|
| Linux/glibc | **0** (A/B/D/E) | **6/22** (T-e, clang-14) |
| Darwin (this Mac) | **22/22** (T-d, gcc-16) | **22/22** (C baseline, apple-clang 21) |

Scoring my own calls: T-b correct (falsified), T-c correct (bound held),
T-d correct (persist), **T-e wrong as worded** (not “absent” — partial
reproduction a compiler-family slice); joint reading trumps any single
axis: **Darwin is the dominant, necessary-for-the-full-cluster variable;
clang-family alone reproduces 6/22 at fixed Linux runtime; the two
factors interact rather than exclude.**

State bookkeeping after the round: cell C restored to canonical recipe
(default-tuning ibex @`352eeeb` rebuilt without trial `CXXFLAGS`,
apple-clang, no extra copts) and re-measured: fails = frozen 22 + the
known `timer_test` flake of that run — `runs/ibex.C.txt` records the
resolution. dreal4 checkout untouched throughout (`51c93b9`, clean).

Open, ranked (nothing below pre-registered yet):
1. **The 16 Darwin-only remainder** (T-e did not reproduce it) — next
   cheapest discriminators: (a) apple-clang-21 vs LLVM-21 *on this Mac*
   (version axis at fixed runtime — if the full-22 needs Apple's clang,
   it's codegen; if LLVM-21 also gives 22, it's Darwin runtime); (b)
   clang-18@ubuntu-24 image (version axis at fixed Linux) to see if the
   6-slice grows toward 22. (c) `fenv`/rounding-mode and knife-edge
   margin probes aimed at `github_issue_192`'s linear-arithmetic path
   under Darwin (1-ulp libm + boundary-shave joint hypothesis).
2. dreal4 conclusion commits queued: `-Wno-deprecated-builtins` breaks
   clang < 16 builds under `-Werror` (measured in T-e), alongside the
   already-queued `gmp_repository` arch probe + `-Wdangling-referenence`.
   (Every trial that passed at 445/445 did so with **no code change** —
   the mac cluster is still an environment-attributed, not-yet-root-caused
   finding; “all tests passing” is NOT yet reached.)

### T-g (added after user green-lit it): LLVM-project clang on this Mac

Trial added when the round-5 discussion was "something about this Mac —
like a bug in Apple's compilers?": the sharpest test of *that* is a
third, independent compiler at fixed OS/SDK/libm/HW. Run = LLVM-project
clang 23.1.4 (brew `llvm`, unmodified upstream) against dreal + ibex,
stdio-headers pinned to Apple's SDK set, after 3 registered infrastructure
accommodations (LLVM's bundled libc++23 headers degrade `std::result_of`
at -std=c++17; clang23's driver injects `-fdepfile-entry=<SDK>/SDKSettings.json`
into every TU which bazel's absolute-path validator rejects; bazel's
builtin-dir parser reads probe *stderr* only). Result: **valid 445/445
run, failing set byte-identical — all 22 (+ the usual flake).** Ledger
verdict: **fork exonerated** (branch as registered, `report.md`
T-g pre-registration).

Complete grid, now with three compilers on macOS:

| runtime → / compiler | gcc | clang (LLVM upstream, non-Apple) |
|---|---|---|
| **Linux/glibc** | 0/22 (A/B/D/E) | 6/22 (T-e, clang-14) |
| **darwin (this Mac)** | 22/22 (T-d, gcc-16) | 22/22 apple-clang-21 (C) **and** 22/22 brew LLVM 23 (T-g) |

Narrowing after T-g: excluded = dreal code, ibex source, fp-flags,
−ffp-contract, libm tables at face value, compiler *vendor* AND compiler
*fork* AND compiler *version* on mac (21 apple / 23 upstream / 16 gcc all
agree). **Remaining, in priority order:** (1) Darwin machine/runtime state
— rounding mode / flush-to-zero around the process (affects every compiler
identically; explains T-d + T-g symmetry); (2) system libc++/libm at
knife-edge decision points (T-c's ≤1-ulp differences amplified where an
interval box sits exactly on a branch condition); (3) SDK/library
implementation seams outside libc++ headers (fenv(), lround, nextafter
routing through Apple's libm inside otherwise-pure-arithmetic code paths —
explains why pure-linear `github_issue_192` clusters only on darwin).
Next cheapest discriminator (not yet run): a value-trace probe — same
expression evaluated at each contractor step, printed on mac and inside
cell D's container, first fork whose double *bit patterns* differ tells
which of (1)/(2)/(3) it is. T-g cost/credits: 4 attempts, 3 shims, all
registered before outcomes; cell C restored to canonical recipe and
re-measured 423/22 (baseline exact).

## Round 6 — strip-back (user-directed): falsified knobs out of the default path

Direction: the trial round is over; nothing falsified should remain a
*default*. Evidence is append-only — each strip is its own commit, gates
pre-registered in `report.md` before running, revert-if-regressed owned
by the caller.

| stripped | where | gate |
|---|---|---|
| ibex source-build tag (`352eeeb`) as cell C's **default** (the "ibex tag we added") | `cells.env` default now **empty** → stock PATH pkg-config → Homebrew `ibex@2.7.4_13` = the pre-trial recipe; `run-cell.sh` only exposes shim/`IBEX_PC_DIR` when `CELL_C_IBEX_PREFIX` is explicitly set (knob kept, documented in both files) | gate 1: 445/445 executed, receipt `stock PATH pkg-config, 2.7.4`, failing set = frozen 22 + `timer_test` flake → **passed, kept** |
| trial build prefixes `~/.local/opt/{ibex-352eeeb-gcc, -llvm, -llvm2, gmp-gcc16}` | untracked disk only; **zero** default-path references remain (checker: repo grep, opt-in shims exempt). Rebuild recipes kept below | gate 2 (bundled): full five-cell run |
| — (kept deliberately, both buckets already classified above) | `install-ibex.sh` portability/`IBEX_CSTDINT_FIX`, `test-driver.sh` validity checks, trial shim files + `Containerfile.trial-clang`/`run-trial-e.sh`/`probe-libm.py` (opt-in receipts `report.md` points at) | — |

**Gate 2 result (the registered run): A 445/445; B 445/445; C 423/22
byte-identical to the frozen set; D 444 (known `-Wdangling-reference`
unbuild); E 444 (same + `timer_test` flake)** — every target inside the
registered ±flake allowances ⇒ **no regressions; both strips kept, none
reverted.** Also done in this round: dreal4's four pinned commits pushed
(`e6d31b4..51c93b9`, origin/modernize-macos now in sync).

Deleted-prefix rebuild recipes (for reproducing T-d/T-g claims):
- `ibex-…-gcc`: `CC=gcc-16 CXX=g++-16 IBEX_CSTDINT_FIX=1 PREFIX=$HOME/.local/opt/ibex-352eeeb-gcc WAF_PY=/opt/homebrew/bin/python3.10 harness/install-ibex.sh`
- `ibex-…-llvm2`: `brew install llvm`, then `CC=/opt/homebrew/opt/llvm/bin/clang CXX=/opt/homebrew/opt/llvm/bin/clang++ CXXFLAGS="-std=c++0x -nostdinc++ -isystem$(xcrun --show-sdk-path)/usr/include/c++/v1" PREFIX=$HOME/.local/opt/ibex-352eeeb-llvm2 WAF_PY=/opt/homebrew/bin/python3.10 harness/install-ibex.sh`
- `gmp-gcc16`: gmp-6.3.0 with `CC="gcc-16 -std=gnu17" CXX=g++-16 ./configure --prefix=$HOME/.local/opt/gmp-gcc16 && make -j && make install` (feeds `g++-16-compat` shim's `-L`)

### T-h — cross-OS equivalence audit (user: "is ibex really the same mac vs linux?")

Answer: source char-for-char identical except one configure-rewritten
CLP include line; ibex.pc flags identical; **behavior NOT identical:
macOS-built ibex rounds endpoints to nearest, linux-built rounds outward
(1-ulp, arithmetic-only, all transcendentals equal)** — first *observed*
numerical divergence of the project; fesetround probed fine on both OSes
so the failure sits in the compiler↔rounding-control seam. Contradiction
logged: T-d (gcc-16 macOS, 22/22 fail) should then round outward — next
round reconciles (ibex-own cflags line + gcc-mac rounding probe + clang-14
in the T-e image). Full text: report.md T-h; artifacts: runs/T-h-*.

## Round 7 — from observation to root cause (T-i, T-j, K, T-l)

| trial | what | result vs pre-registration |
|---|---|---|
| T-i | rebuild ibex with **gcc-16 on the Mac**, value-probe (resolve T-d collision) | **P1b**: round-to-nearest, byte-equal to apple-clang's → rounding-loss is *compiler-independent on darwin*; T-d collision closed in the mechanism's favour (receipts: `-frounding-math` really was live) |
| T-j | build ibex with **clang-14 on Linux**, same probe (the T-e six-slice) | **P2b**: outward = linux pattern (twice-confirmed incl. fresh 3-`fesetround`-refs lib) → the 6-test slice is **not** rounding; rounding-loss = darwin-exclusive, 2-of-2 compilers per OS |
| K | mechanism read: digest rounding_control, selector traces, macro matrix, `nm` fenv refs | **Pka taken**: `rounding_control_double.hpp:82` → iso9x(fesetround dance) **iff `__STDC_IEC_559__`**, else **`void` = empty `downward(){}` NOP**; `config.hpp`'s force-define is *commented-out code, identical both sides* (**Pkb falsified**: `-frounding-math` defines nothing anywhere). Macro declared by glibc chain (linux g++ native=1, clang-14 0→1 via `<iostream>`), **never by any darwin toolchain chain (0,0)** ⇒ **root cause of the 22-test cluster: macOS ibex has no directed rounding at all → non-rigorous intervals → C1 wrong-unsat-with-witness.** OS-level `fesetround` proven fine (fix site = selector, not OS) |
| T-l | **your upgrade trial: ibex 2.9.1** (gates + value probe + cell run) | G-base passed (stock stays 2.7.4); P-sel/P-behav **falsified in the hoped direction**: 2.9 = **gaol-family kernel** (old `filib rounding_control` gone entirely) with **outward darwin rows**; cell run = **invalid / P-build taken** (285 fail-to-build) — census: **16 errors / 12 classes / 4 files** (`LinearizerCombo→Compo`, `ContractorIbexPolytope` inheritance, `Box` nothrow-move asserts) → **port is small**; P-fix/P-persist remain unresolved pending a port |

Two competing fix paths now stand, pre-registration queued for next:
**(i) macro-force** (`-D__STDC_IEC_559__` into the *building* of ibex
+ dreal copts — pure trial knobs, no source edits; mechanism says iso9x
gets selected and darwin is *proven* to honor it) vs **(ii) port dreal
to 2.9** (real code, ~4 files per census, kernel switched to gaol which
is outward on darwin by measurement).

## Isolation test — `isolation/` (artifact, not an intervention; appended with the K round)

Root cause **K** now has a runnable witness that contains **no dreal
code at all** — only `<fenv.h>` and ibex — per the standing constraints
(pin pristine, tests never touch solver logic, the frozen 445-target
denominator inside dreal4 untouched):

```bash
isolation/run.sh                      # this Mac
isolation/run.sh --container[=IMAGE]  # linux cell image (22.04 / 24.04 / fedora-43)
isolation/run.sh --dreal <binary>     # + the 4-line fixture through dreal
```

Four checks: `[1]` OS `fesetround` (control), `[2]` ibex's own
`rounding_control` selector, `[3]` `ibex::Interval` enclosure, `[4]` an
ibex-only replay of `ContractorIbexFwdbwd`'s backward pass on a
witness-bearing linear capsule — the wrong-`unsat` itself, inside the
dependency. **Measured: darwin 1/4 pass ([2][3][4] red = the cluster);
linux images 4/4 green (3/3 images); `--dreal` on the fixture answers
`unsat` here (the fixture is in no cell's suite; its ancestor
`github_issue_192` is `delta-sat` in cells A/B/D/E — runs/failed.*.txt).**
No dreal code path is involved, so red-on-darwin/green-on-linux is a
statement about the dependency, which is what trial 5 + K claimed.

Gate-measurement for the pending fix path (i), already taken:
`TEST_CXXFLAGS='-D__STDC_IEC_559__' isolation/run.sh` → **3/4** — `[2]`
and `[3]` flip green (they compile ibex's headers in the test's own TU =
any consumer TU, dreal's included) while `[4]` stays red (it runs code
compiled into `libibex`). So `-D__STDC_IEC_559__` must reach **both** the
ibex build and dreal's copts; one command reads out both halves.

Provenance of the 4-line fixture (all dreal answers measured on this
Mac): `github_issue_192` → drop `worklist-fixpoint` + unused assert →
`(< (- 8.787792382 567495437.0 r0) 0.0)` → constants swept until
`(< (- 0.1 10 r0) 0.0)`. Exact-decimal constants (1.0, 0.5, 0.25) fold
to a point and never fail; inexact decimals become ibex "capsules" —
the literals that round-to-nearest can collapse — but not every capsule
fails: the boundary is the backward round-trip landing outside, not the
input grammar (scan table in the fixture's header). Scope = the C1 wrong-unsat
family only (trial-5 rubric: `timer_test`, `get_value_01` drift and the
C2 rosenbrock pair are **not** this test's subject). Detail:
`isolation/README.md`.

## Round 8 — T-m: fix path (i) executed — force the rounding selector

| trial (hypothesis tested) | what we did | effect on the tests | verdict |
|---|---|---|---|
| T-m: cell C's 22 = ibex's `__STDC_IEC_559__`-guard selecting the void rounding strategy; untaping ibex/filib's own commented-out force-define fixes it | `IBEX_FORCE_IEC559=1` in `harness/install-ibex.sh` generates one 451-byte patch beside the bundled filib archive so waf's own `apply_all_relevant_patches` applies it between extraction and compile (guarded `#if !defined` ⇒ no-op on Linux; default off; knobs only — no dreal code, Homebrew untouched, pin pristine); source-build `352eeeb` → `~/.local/opt/ibex-352eeeb-iec559` (trial-4 recipe + the one env var); cell run via the existing `CELL_C_IBEX_PREFIX` knob | **P1 taken** (registered ≥14 flips): **23/23 baseline labels flip, 0 new** … **P2 taken** (comm col-2 empty) … **P3 taken** (445/445 executed, "no loading errors") … **P1b taken-and-sharpened**: registered kept ⊆ {rosenbrock×2, get_value_01, ea_01, github_issue_201}, measured kept = **∅** | **Root cause K → confirmed at cell level with a knob.** Mechanism gates first (`runs/T-m-gate.txt`: waf applied the patch by name, header untaped, `nm -u` fesetround refs 0 brew / 0 trial-4 / 1 patched, isolation test 1/4 baseline preserved → **4/4 patched**), then the cell: cell C = **445/445** (`runs/failed.C.txt` empty, `runs/ibex.C.txt` records the prefix, scoring in `runs/T-m-scoring.txt`, registration in report round 8 committed before the run) |

**Ledger amendments forced by T-m's kept-set:**

- **Trial 5's erratum classes were read through the defect itself.** C2
  ("both answers legal") flipped → the pair's `unsat` was never
  licensed; C4 (`get_value_01` "value-drift, no flip") flipped → its ULP
  was the same non-rigorous arithmetic, so the T-c libm reading is a
  true measurement but *not* this cause; both C3s resolved. Recount: the
  frozen cluster is **22/22 one root cause**, not "at most 20".
- **Fix path (ii)** (dreal→ibex 2.9/gaol port, T-l census) **demoted to
  plan B for correctness** — (i) measured. T-l's port census remains
  recorded insurance; the gaol-outward observation now explains why 2.9
  would also have worked.
- `//dreal/util:timer_test` (flake, unscored) passed in this run;
  unaffected provenance stands (it flaked in every cell at least once).

**Status now:** knob **opt-in** (`CELL_C_IBEX_PREFIX` + `IBEX_FORCE_IEC559=1`
recipe in report round 8); `runs/` artifacts record the trial
configuration until either (a) the default is switched (decision +
cells.env/README commit) or (b) a base-config restore run (round-6
pattern) overwrites them. Record `runs/T-m-failed.txt` = empty file
(0 failing labels) next to `runs/T-m-scoring.txt`.

**Update 8b (decision, post-scoring): DEFAULTED.** `CELL_C_IBEX_PREFIX`
now defaults to the patched prefix (recipe + opt-out `CELL_C_IBEX_PREFIX=`
base-config documented in cells.env), `run-cell.sh` fails loudly on any
un-patched prefix (escape `CELL_C_IBEX_ACCEPT_UNPATCHED=1`, recipe in
the error), `install-ibex.sh` itself stays default-off so reference
images remain byte-identical. Gates: `runs/T-m-default-gate.txt` —
negative test refused rc=1; three default-path runs with **cluster = 0**
each (only the registered-unscored `timer_test` flake; passes standalone
and in the scored run ≈ 3/4 flake under full-cell load); `no loading
errors`; receipts show the default prefix. Committed collector state:
`runs/failed.C.txt` = [`//dreal/util:timer_test`],
`runs/completeness.C.txt` = 445/445 executed,
`runs/SUMMARY.md` regenerated.

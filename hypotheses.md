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

## Next trials (in order; each gets a pre-registered prediction in `report.md`, then runs as a cell C re-run — C overwrites in git, this ledger records the verdict)

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

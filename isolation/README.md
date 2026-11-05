# `isolation/` — the 22-test cluster, isolated (no dreal code)

A characterization test for the root cause recorded in the round-7 **K**
row of [`../hypotheses.md`](../hypotheses.md): on macOS, ibex's bundled
`filib` interval library ends up on the **void rounding-control strategy**
(`rounding_control_double_void.icc`: `downward() {}` — a NOP), because
`__STDC_IEC_559__` is never defined by any darwin toolchain header chain
and ibex's own force-define is commented out. Round-to-nearest interval
endpoints ⇒ non-rigorous enclosure ⇒ ibex's forward/backward propagation
empties a strictly satisfiable constraint ⇒ every solver built on it must
answer `unsat` with a witness in hand — the failure mode of the frozen
22-target cell-C cluster.

The test deliberately contains **zero dreal code**: only `<fenv.h>` and
ibex. So it cannot affect solver behaviour (ground rule 2), it does not
touch the pristine `dreal4/` pin, and it does not perturb the frozen
445-target accounting. It repeats the investigation's narrowing in
miniature: `github_issue_192` (pure linear, no quantifiers, no libm) →
`(< (- 8.787792382 567495437.0 r0) 0.0)` → 4-line
[`wrong_unsat.smt2`](wrong_unsat.smt2) → the ibex-only graph below.

## Run

```bash
isolation/run.sh                          # this machine (pkg-config ibex)
isolation/run.sh --container[=IMAGE]      # rebuild inside the Linux reference
                                          # cell image (dreal-ref:22.04 …)
isolation/run.sh --dreal path/to/dreal    # + the 4-line fixture through dreal
```

Exit **0** = the dependency behaves on this system, exit **1** = the bug
reproduces here. `--dreal` adds one informational check (the test itself
never runs dreal).

## Measured matrix (all four checks, written 2025-11 while root-causing)

| check | what it asserts | darwin / cell C | linux `dreal-ref:22.04` | linux `24.04` | linux `fedora-43` |
|---|---|---|---|---|---|
| `[1]` `os-fesetround` | `fesetround(FE_DOWNWARD/UP)` changes `a+b` under ibex's own copts (control) | PASS | PASS | PASS | PASS |
| `[2]` `ibex-rounding-selector` | ibex's compiled `filib::rounding_control<double,bool>` really engages directed rounding | **FAIL** | PASS | PASS | PASS |
| `[3]` `ibex-interval-enclosure` | `Interval(-10.0) + [capsule of 0.1]` brackets the exact real sum (bounds from check `[1]`) | **FAIL** (width 0, loses the upper end) | PASS | PASS | PASS |
| `[4]` `ibex-wrong-unsat` | ibex's `Function::backward` keeps a non-empty box for a constraint with a verified witness | **FAIL** (box → `empty` ⇒ `unsat`) | PASS | PASS | PASS |
| `--dreal` | `wrong_unsat.smt2` through a dreal binary | `unsat` (FAIL) | not in any cell's suite — its ancestor `github_issue_192` is `delta-sat` in cells A/B/D/E (`runs/failed.*.txt`), and `[4]` above is the Linux answer of the identical dependency path | — | — |

`[1]` green on both sides is the important control: the OS rounding
hardware/API works everywhere (`runs/T-h-fenv.txt` measured the same), so
the defect sits where check `[2]` says it does — in the *strategy ibex
compiles itself* — and `[3]`/`[4]` are the two consequences (lost
enclosure, empty box). Red on darwin **is** the cluster; green on linux
is why no Linux cell has ever seen it.

## What each check is, in one line each

1. **`os-fesetround`** — computes `down(0.1+(-3))` / `up(0.1+(-3))`
   directly with `fesetround` and `volatile` doubles, with `pkg-config`
   cflags (i.e. ibex's `-frounding-math`) in force. Excludes "the machine
   can't round outward".
2. **`ibex-rounding-selector`** — calls ibex's own
   `rounding_control<double,false>` / `<double,true>` `.downward()` /
   `.upward()` and requires `fegetround()` to move. Prints whether
   `__STDC_IEC_559__` was defined in this TU, i.e. which strategy header
   branch `rounding_control_double.hpp` picked. This is the root cause
   proper (report.md K).
3. **`ibex-interval-enclosure`** — `Interval(-10.0) + [nextafter(0.1,0),
   nextafter(0.1,inf)]` must satisfy `lb ≤ down(exact)` and `ub ≥
   up(exact)`, where `down/up` come from check `[1]`. On darwin both
   endpoints round to the same double: width 0, exact hull lost.
4. **`ibex-wrong-unsat`** — replays, in 15 lines of pure ibex, the exact
   expression graph dreal's `IbexConverter` emits for the 4-line fixture
   (two separate constant nodes `-10` and the capsule, variable sub, strict
   `< 0`; `dreal/util/ibex_converter.cc` `VisitAddition` /
   `VisitLessThan`), from `r0 = ENTIRE`, through
   `Function::backward(right_hand_side, box)` — the call
   `dreal/contractor/contractor_ibex_fwdbwd.cc:99` makes. It first verifies
   the witness (`r0 = 0` evaluates strictly negative), then requires a
   non-empty box. Larger details: the dreal trace that pointed here is in
   the commit message.

Not a synthetic idiom: the same collapse reproduced end-to-end through
`dreal4/bazel-bin/dreal/dreal` before any of this was written — full
`--verbose trace` shows `ContractorIbexFwdbwd::Prune` taking
`r0 : [ ENTIRE ] -> [ empty ]` and `Theroy Check = UNSAT` for the fixture
(and for the unminimized `github_issue_192` that cell C's own suite
fails on: `runs/failed.C.txt`).

## Reading fix attempts with this test

The selector is **compile-time**, and the checks disagree in a way that
matters. Measured on this Mac:

```bash
TEST_CXXFLAGS='-D__STDC_IEC_559__' isolation/run.sh    # -> [1] PASS [2] PASS [3] PASS [4] FAIL (3/4)
```

`[2]`/`[3]` are evaluated *in the test's own TU* — ibex's interval
headers are inline code, so this is exactly the situation every
**consumer** TU of ibex headers is in, dreal's included. `[4]`
(`Function::backward`) executes code compiled into `libibex` itself,
which on this machine was built without the define and stays void. So a
green `[4]` proves `libibex` is built right, green `[2]`/`[3]` prove the
*consumer's* copts are right: the define has to reach **both** the build
of ibex and the copts of dreal — verbatim the ledger's fix path (i) —
and this test reads out both halves with one command, so the pending fix
gate can use it directly.

## Scope — what this test does NOT claim

Per the round-7 classification of the frozen 22 (hypotheses trial 5):
this isolates the **C1 wrong-unsat-with-witness** family, i.e. the bulk of
the cluster. Explicitly out of scope:

* `//dreal/util:timer_test` — timing flake, seen in every environment;
* `get_value_01` — one-ULP model value drift (no answer flip); the shared
  round-to-nearest arithmetic is a plausible cause but this test makes no
  claim about it;
* `constrained_opt_rosenbrock_{cubic,disk}` — classified C2: both answers
  legal;
* the integer/cpplint buckets — already attributed (round 1–3).

## Files

| file | role |
|---|---|
| `ibex_rounding_isolation_test.cc` | the test: four checks, `<fenv.h>` + ibex only |
| `run.sh` | build (pkg-config / `IBEX_PREFIX` / container prefix) + run + `--container` / `--dreal` |
| `wrong_unsat.smt2` | provenance fixture: the minimal dreal-level input, with the measured scan in its header |

Evidence it cross-references: `runs/K-mechanism.txt` (selector/macro
matrix), `runs/T-h-fenv.txt` (OS `fesetround` fine both sides),
`runs/T-h-values.{mac,linux}.txt` (first observed divergence: nearest
vs outward), `runs/failed.C.txt` + `runs/bazel-test.C.log` (the frozen
22 + its diffs), `report.md` round-7 (K scored, T-i/T-j receipts).

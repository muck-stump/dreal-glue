# dreal4 cell status

Generated: `2026-11-04T04:07:43Z` by `harness/summary.sh` — do not edit;
regenerated after every run (`harness/run-all.sh`). Evidence lives in git.

| cell | code | environment | result |
|---|---|---|---|
| A | `f93bdcc` — original code | ubuntu 22.04 reference container (podman) | **445/445 PASS ✓** |
| B | `e6d31b4` — modernized | ubuntu 22.04 reference container (podman) | **1/445 failing ✗** |
| C | `51c93b9` — modernized (submodule pin) | this Mac, host cell (macOS 27.0.1, Apple Silicon) | **22/445 failing ✗** |
| D | `e6d31b4` — modernized | ubuntu 24.04 container (podman) | **1/445 failing ✗** |
| E | `e6d31b4` — modernized | fedora 43 container (podman) | **1/445 failing ✗** |

**A vs B: identical apart from the known `timer_test` timing flake** (recorded in
failed lists when it flakes; pre-registered category — see report.md). No
code-vs-code divergence.

## Cell B —        1 failing target(s)
```
//dreal/util:timer_test
```

## Cell C —       22 failing target(s)
```
//dreal/api:api_test
//dreal/api:cav18_benchmark_with_local_opt
//dreal/api:cav18_benchmark_without_local_opt
//dreal/test/dr:constrained_opt_rosenbrock_cubic
//dreal/test/dr:constrained_opt_rosenbrock_disk
//dreal/test/dr:unconstrained_opt_beale
//dreal/test/dr:unconstrained_opt_eggholder
//dreal/test/dr:unconstrained_opt_mccormick
//dreal/test/dr:unconstrained_opt_poly1
//dreal/test/python:api_test
//dreal/test/python:github_issue_154
//dreal/test/smt2:ea_01
//dreal/test/smt2:ea_beale
//dreal/test/smt2:exist_forall_04
//dreal/test/smt2:exist_forall_06
//dreal/test/smt2:exist_forall_07
//dreal/test/smt2:exist_forall_08
//dreal/test/smt2:exist_forall_10
//dreal/test/smt2:get_value_01
//dreal/test/smt2:github_issue_192
//dreal/test/smt2:github_issue_201
//dreal/test/smt2:minimize_03
```

## Cell D —        1 failing target(s)
```
//dreal/contractor:contractor_ibex_fwdbwd_test
```

## Cell E —        1 failing target(s)
```
//dreal/contractor:contractor_ibex_fwdbwd_test
```


Raw artifacts per cell: `runs/failed.<cell>.txt`, `runs/completeness.<cell>.txt`,
`runs/env-manifest.<cell>.txt`, `runs/bazel-test.<cell>.log`.

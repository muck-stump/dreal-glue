# dreal4 cell status

Generated: `2026-11-05T03:42:53Z` by `harness/summary.sh` — do not edit;
regenerated after every run (`harness/run-all.sh`). Evidence lives in git.

| cell | code | environment | result |
|---|---|---|---|
| A | `f93bdcc` — original code | ubuntu 22.04 reference container (podman) | **445/445 PASS ✓** |
| B | `e6d31b4` — modernized | ubuntu 22.04 reference container (podman) | **445/445 PASS ✓** |
| C | `51c93b9` — modernized (submodule pin) | this Mac, host cell (macOS 27.0.1, Apple Silicon) | **445/445 PASS ✓** |
| D | `e6d31b4` — modernized | ubuntu 24.04 container (podman) | **1/445 failing ✗** |
| E | `e6d31b4` — modernized | fedora 43 container (podman) | **2/445 failing ✗** |

**A vs B (the code question): identical** — both cells have the same
(empty) failing set; `comm -3 runs/failed.A.txt runs/failed.B.txt` is empty.

## Cell D —        1 failing target(s)
```
//dreal/contractor:contractor_ibex_fwdbwd_test
```

## Cell E —        2 failing target(s)
```
//dreal/contractor:contractor_ibex_fwdbwd_test
//dreal/util:timer_test
```


Raw artifacts per cell: `runs/failed.<cell>.txt`, `runs/completeness.<cell>.txt`,
`runs/env-manifest.<cell>.txt`, `runs/bazel-test.<cell>.log`.

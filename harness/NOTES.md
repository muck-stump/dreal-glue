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
  `.bazelrc` and `setup/mac/*` changed).

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

## Status

- [x] podman installed + machine created (6.1.4, applehv, arm64, 8/12288/60,
      no `--rosetta` option in this version)
- [x] harness written (`Containerfile`, `cells.env`, `install-bazel.sh`,
      `in-container-test.sh`, `run-cell.sh`, `collect.sh`)
- [x] gpg-agent root cause, fix in Containerfile (container-side)
- [ ] reference image `dreal-ref:22.04` builds
- [ ] cells A + B run in parallel, collected to `runs/failed.{A,B}.txt`
- [ ] `report.md`: `comm -3` diff + attribution; record image ID + `dpkg -l`
      manifest as env-equality evidence; score the cell-C predictions
      (119 cpplint / 21 unsat-cluster / `get_value_01` / `timer_test`)
- [ ] conclusions folded into `dreal4/README.md` as docs commits
- [ ] optional tier-0 smoke: prebuilt `dreal/dreal4` image on the failing
      cell-C inputs (indicative only)

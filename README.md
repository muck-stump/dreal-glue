# dreal

Glue repository for testing **dreal4** across versions and environments.

## What is what

- `dreal4/` is a git submodule of the **actual repository**: dReal's
  source code, build fixes, tests, and its own README live there, and
  everything that changes solver behavior happens there (in small,
  reviewable commits) — never here.

- This repository (`dreal`) is the glue that holds things together when
  multiple versions of things need to be tested: it pins *which* commit
  of dreal4 sits in the tree, and over the runs it will hold the test
  harness (run scripts), the per-run artifacts (one sorted list of
  failing test targets per run), and the A/B comparison reports
  between versions and environments. It contains no solver code.

Keeping the harness outside dreal4 is deliberate: a checkout under test
must be bit-for-bit identical to the commit being compared, so the
instrumentation cannot live in the same tree.

## Layout

```
dreal4/            submodule → git@github.com:muck-stump/dreal4.git
                   .gitmodules pins the `modernize-macos` branch
```

## Usage

Create the workspace (submodule included):

```bash
git clone --recurse-submodules <this-repo>
cd dreal
git -C dreal4 log --oneline -1     # show the pinned commit
```

Check out a different version under test, then record the new pin:

```bash
git -C dreal4 fetch origin
git -C dreal4 checkout <commit>     # e.g. the modernization base, or a branch tip
git add dreal4                      # done from this (super)repository
```

Note: `git submodule update --remote` moves the submodule to the tip of
the branch named in `.gitmodules`; most comparison runs should instead
pin explicit commit ids, as described in the test reports.

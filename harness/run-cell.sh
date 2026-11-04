#!/usr/bin/env bash
#
# Start one cell as a detached container:
#   run-cell.sh <cell>        (ids, images and commits: harness/cells.env)
#
# Materializes the cell's pinned commit (via `git archive`, so the tree is
# bit-for-bit the commit: no .git, no worktree dirt) into a per-cell volume,
# then starts a container from that cell's image to run `bazel test //...`.
# (Image is built first if its tag is missing — see cells.env.) Cells are
# fully independent — separate source volume, separate Bazel cache volume —
# so cells run in parallel.
#
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=cells.env
source "$ROOT/harness/cells.env"

CELL=${1:?usage: run-cell.sh <cell>   (known cells: $CELLS)}
cell_known "$CELL" || {
  echo "unknown cell: $CELL (known cells: $CELLS)" >&2; exit 1; }
COMMIT=$(cell_commit "$CELL")
IMAGE=$(cell_image "$CELL")

# Sanity: the pinned commit must be available in the submodule, and the
# submodule must be clean (a dirty tree next to a "pristine" claim goes
# unnoticed otherwise).
git -C "$ROOT/dreal4" cat-file -e "$COMMIT^{commit}" || {
  echo "commit $COMMIT not found in dreal4/ — fetch first" >&2; exit 1; }
test -z "$(git -C "$ROOT/dreal4" status --porcelain)" || {
  echo "dreal4/ has uncommitted changes; the A/B needs a pristine checkout" >&2; exit 1; }

# Host cell: no image — the checkout under test is the submodule itself,
# run bare on this machine with the same shared driver, artifacts staged in
# runs/ where collect.sh harvests them like any cell volume.
if [ "$(cell_kind "$CELL")" = host ]; then
  HEAD_SHA=$(git -C "$ROOT/dreal4" rev-parse HEAD)
  [ "$HEAD_SHA" = "$COMMIT" ] || {
    echo "cell $CELL: dreal4 HEAD $HEAD_SHA != pinned commit $COMMIT" >&2; exit 1; }

  # Cell C recipe knob — the ibex swap. dreal's @ibex repository rule takes
  # PKG_CONFIG_PATH ONLY from dreal4/dreal/workspace.bzl's committed list,
  # which ends at Homebrew's ibex (2.7.4_13, 2021); it tracks PATH (the
  # pkg-config "binary" it resolves), so preppend our shim dir, point it at
  # the harness source-build of the SAME ibex commit the Linux cells use
  # (352eeeb), and restart the bazel server so PATH actually reaches the
  # rule. Missing prefix = loud pkg-config failure, never silent brew fallback.
  export IBEX_PC_DIR="$CELL_C_IBEX_PREFIX/share/pkgconfig"
  [ -f "$IBEX_PC_DIR/ibex.pc" ] || {
    echo "cell $CELL: no ibex.pc at $IBEX_PC_DIR" >&2
    echo "  build it:  PREFIX=\"$CELL_C_IBEX_PREFIX\" WAF_PY=/opt/homebrew/bin/python3.10 harness/install-ibex.sh" >&2
    exit 1; }
  export PATH="$ROOT/harness/shim-bin:$PATH"
  # Trial hook (hypotheses.md T-b/…): extra bazel CLI args, host cell only,
  # passed through from the invoking shell — normal runs pass none.
  export BAZEL_EXTRA_ARGS="${CELL_BAZEL_EXTRA_ARGS:-}"
  (cd "$ROOT/dreal4" && bazel shutdown >/dev/null 2>&1) || true

  STAGE="$ROOT/runs/.stage-$CELL"
  rm -rf "$STAGE"; mkdir -p "$STAGE"
  # Record *which* ibex this run resolved (thru the shim) — the evidence that
  # the swap is in effect, harvested by collect.sh into runs/ibex.<cell>.txt.
  {
    echo "# cell $CELL ibex resolution (queried thru harness/shim-bin/pkg-config)"
    echo "IBEX_PC_DIR=$IBEX_PC_DIR"
    echo "modversion: $(pkg-config --modversion ibex 2>&1 || true)"
    echo "libs:       $(pkg-config --libs ibex 2>&1 || true)"
  } > "$STAGE/ibex.txt"
  echo "cell $CELL (host): testing $HEAD_SHA at $ROOT/dreal4"
  rc=0
  "$ROOT/harness/test-driver.sh" "$STAGE" "$ROOT/dreal4" || rc=$?
  echo "cell $CELL finished (bazel rc=$rc) — now: harness/collect.sh $CELL"
  exit 0
fi

cell_ensure_image "$CELL"

NAME="dreal-cell-$CELL"
SRC_VOL="dreal-cell-$CELL-src"
BAZEL_VOL="dreal-cell-$CELL-bazel"

podman volume exists "$SRC_VOL" 2>/dev/null || podman volume create "$SRC_VOL" >/dev/null
podman volume exists "$BAZEL_VOL" 2>/dev/null || podman volume create "$BAZEL_VOL" >/dev/null
podman rm -f "$NAME" >/dev/null 2>&1 || true

echo "cell $CELL: materializing $(git -C "$ROOT/dreal4" rev-parse "$COMMIT")"
git -C "$ROOT/dreal4" archive --format=tar "$COMMIT" |
  podman run --rm -i -v "$SRC_VOL":/work "$IMAGE" \
    bash -c 'rm -rf /work/src && mkdir -p /work/src && tar -xf - -C /work/src'

podman run -d --name "$NAME" \
  -v "$SRC_VOL":/work \
  -v "$BAZEL_VOL":/root/.cache/bazel \
  "$IMAGE" /usr/local/bin/dreal-cell-test

echo "cell $CELL started: container $NAME"
echo "  follow: podman logs -f $NAME"
echo "  finish: harness/collect.sh $CELL"

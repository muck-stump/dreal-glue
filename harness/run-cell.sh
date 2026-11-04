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

#!/usr/bin/env bash
#
# Harvest a finished cell: runs/failed.<CELL>.txt (sorted labels, the repo's
# comparison artifact), plus the raw log and exit code next to it.
#
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=cells.env
source "$ROOT/harness/cells.env"
CELL=${1:?usage: collect.sh <cell>   (known cells: $CELLS)}
cell_known "$CELL" || {
  echo "unknown cell: $CELL (known cells: $CELLS)" >&2; exit 1; }
IMAGE=$(cell_image "$CELL")
NAME="dreal-cell-$CELL"

echo "waiting for $NAME ..."
podman wait "$NAME" >/dev/null

mkdir -p "$ROOT/runs"
podman run --rm \
    -v "dreal-cell-$CELL-src":/work:ro \
    -v "$ROOT/runs":/out \
    "$IMAGE" \
    bash -c "
      sort -u /work/failed.txt > /out/failed.$CELL.txt
      cp /work/flaky.txt       /out/flaky.$CELL.txt
      cp /work/bazel-test.log  /out/bazel-test.$CELL.log
      cp /work/exit-code.txt   /out/exit-code.$CELL.txt
      cp /work/completeness.txt /out/completeness.$CELL.txt
    "

echo "collected:"
echo "  runs/failed.$CELL.txt        ($(wc -l < "$ROOT/runs/failed.$CELL.txt") failing targets, bazel rc=$(cat "$ROOT/runs/exit-code.$CELL.txt"))"
echo "  runs/flaky.$CELL.txt         ($(wc -l < "$ROOT/runs/flaky.$CELL.txt") flaky-then-passed)"
echo "  runs/completeness.$CELL.txt:"
sed 's/^/    /' "$ROOT/runs/completeness.$CELL.txt"
echo "  runs/bazel-test.$CELL.log    (full log)"

# Environment manifest for this cell: one file per image, so the report can
# cite exactly what the cell ran on (same content class as runs/env-manifest.txt
# for cells A/B: os-release, tool versions, full package list).
IMG_ID=$(podman image inspect -f '{{.Id}}' "$IMAGE")
{
  echo "# cell $CELL environment manifest"
  echo "# image: $IMAGE ($IMG_ID)"
  podman run --rm "$IMAGE" bash -c '
    cat /etc/os-release
    echo "arch: $(uname -m)"
    echo "bazel: $(bazel --version 2>/dev/null || echo unavailable)"
    echo "gcc: $(g++ --version 2>/dev/null | head -1)"
    echo "python: $(python3 -V 2>&1)"
    for p in ibex clp nlopt gmp; do
      echo "$p: $(pkg-config --modversion "$p" 2>/dev/null || echo n/a)"
    done
    echo
    if command -v dpkg >/dev/null; then dpkg -l; else rpm -qa | sort; fi
  '
} > "$ROOT/runs/env-manifest.$CELL.txt"
echo "  runs/env-manifest.$CELL.txt   (image $IMAGE, $(basename "$IMG_ID" | cut -c1-12)…)"

podman rm -f "$NAME" >/dev/null

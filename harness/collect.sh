#!/usr/bin/env bash
#
# Harvest a finished cell: runs/failed.<CELL>.txt (sorted labels, the repo's
# comparison artifact), plus the raw log and exit code next to it.
#
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CELL=${1:?usage: collect.sh A|B}
NAME="dreal-cell-$CELL"

echo "waiting for $NAME ..."
podman wait "$NAME" >/dev/null

mkdir -p "$ROOT/runs"
podman run --rm \
    -v "dreal-cell-$CELL-src":/work:ro \
    -v "$ROOT/runs":/out \
    "$(source "$ROOT/harness/cells.env"; echo "$CELL_IMAGE")" \
    bash -c "
      sort -u /work/failed.txt > /out/failed.$CELL.txt
      cp /work/flaky.txt       /out/flaky.$CELL.txt
      cp /work/bazel-test.log  /out/bazel-test.$CELL.log
      cp /work/exit-code.txt   /out/exit-code.$CELL.txt
    "

echo "collected:"
echo "  runs/failed.$CELL.txt        ($(wc -l < "$ROOT/runs/failed.$CELL.txt") failing targets, bazel rc=$(cat "$ROOT/runs/exit-code.$CELL.txt"))"
echo "  runs/flaky.$CELL.txt         ($(wc -l < "$ROOT/runs/flaky.$CELL.txt") flaky-then-passed)"
echo "  runs/bazel-test.$CELL.log    (full log)"
podman rm -f "$NAME" >/dev/null

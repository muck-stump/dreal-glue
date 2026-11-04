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

# Host cell: harvest the driver's staging dir instead of a container volume,
# and write an env manifest of the machine itself (the macOS equivalent of
# collect.sh's dpkg/rpm dump: OS build, toolchain, library versions, git pin).
if [ "$(cell_kind "$CELL")" = host ]; then
  STAGE="$ROOT/runs/.stage-$CELL"
  [ -f "$STAGE/failed.txt" ] || {
    echo "no staged run for cell $CELL (runs/.stage-$CELL) — run-cell.sh $CELL first" >&2; exit 1; }
  sort -u "$STAGE/failed.txt"  > "$ROOT/runs/failed.$CELL.txt"
  cp "$STAGE/flaky.txt"        "$ROOT/runs/flaky.$CELL.txt"
  cp "$STAGE/bazel-test.log"   "$ROOT/runs/bazel-test.$CELL.log"
  cp "$STAGE/exit-code.txt"    "$ROOT/runs/exit-code.$CELL.txt"
  cp "$STAGE/completeness.txt" "$ROOT/runs/completeness.$CELL.txt"
  {
    echo "# cell $CELL environment manifest (host cell: this Mac, bare metal)"
    echo "# commit under test: $(git -C "$ROOT/dreal4" rev-parse HEAD)"
    sw_vers
    echo "arch: $(uname -m)"
    echo "clang: $(clang --version 2>/dev/null | head -1)"
    echo "python (pinned for py_tests): $(/opt/homebrew/bin/python3.14 -V 2>&1)"
    echo "host default python3 (NOT used): $(python3 -V 2>&1)"
    echo "bazel: $(cd "$ROOT/dreal4" && bazel --version 2>/dev/null)  # bazelisk honours .bazelversion"
    for p in ibex clp nlopt gmp; do
      echo "$p: $(pkg-config --modversion "$p" 2>/dev/null || echo n/a)"
    done
    echo
    echo "--- dreal4 git ---"
    git -C "$ROOT/dreal4" log --oneline -5
  } > "$ROOT/runs/env-manifest.$CELL.txt"
  rm -rf "$STAGE"
  echo "collected (host cell):"
  echo "  runs/failed.$CELL.txt        ($(wc -l < "$ROOT/runs/failed.$CELL.txt") failing targets, bazel rc=$(cat "$ROOT/runs/exit-code.$CELL.txt"))"
  echo "  runs/flaky.$CELL.txt         ($(wc -l < "$ROOT/runs/flaky.$CELL.txt") flaky-then-passed)"
  echo "  runs/completeness.$CELL.txt:"
  sed 's/^/    /' "$ROOT/runs/completeness.$CELL.txt"
  echo "  runs/env-manifest.$CELL.txt"
  echo "  runs/bazel-test.$CELL.log    (full log)"
  exit 0
fi

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

#!/usr/bin/env bash
#
# run-all.sh [<cell> ...] — the one entry point for a round of cells:
# builds any missing image, runs the cells (default: every cell in cells.env,
# A through E), collects their artifacts and prints the comparison against
# cell B (the same code in the reference environment — the diff that decides
# whether anything moved) plus the human-readable summary:
#
#   harness/run-all.sh          # all five cells: A B C D E
#   harness/run-all.sh D E      # just a subset
#
# Cells run in batches of $PARALLEL (default 2): the podman machine is
# 8 CPU / 12 GiB and the per-cell budget inside in-container-test.sh is half
# of that (--jobs=4 / 6 GiB), which is what a cell's numbers were measured
# with. More cells ≠ more parallelism — queue them.
# Force image rebuilds: REBUILD=1 harness/run-all.sh D E
#
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=cells.env
source "$ROOT/harness/cells.env"

[ $# -ge 1 ] || set -- $CELLS   # no args = every cell, A through E
for c in "$@"; do
  cell_known "$c" || { echo "unknown cell: $c (known cells: $CELLS)" >&2; exit 2; }
done
CELLS_TO_RUN=("$@")
PARALLEL=${PARALLEL:-2}

i=0
while [ "$i" -lt "${#CELLS_TO_RUN[@]}" ]; do
  batch=()
  while [ "${#batch[@]}" -lt "$PARALLEL" ] && [ "$i" -lt "${#CELLS_TO_RUN[@]}" ]; do
    batch+=("${CELLS_TO_RUN[$i]}"); i=$((i + 1))
  done
  for c in "${batch[@]}"; do
    echo "=== starting cell $c ==="
    "$ROOT/harness/run-cell.sh" "$c"
  done
  for c in "${batch[@]}"; do
    echo "=== collecting cell $c ==="
    "$ROOT/harness/collect.sh" "$c"
  done
done

# The verdict per cell: comm -3 against cell B. Equal counts can hide swapped
# targets, so the sorted label lists are compared, never the numbers.
if [ -f "$ROOT/runs/failed.B.txt" ]; then
  for c in "${CELLS_TO_RUN[@]}"; do
    [ "$c" = "B" ] && continue
    echo
    echo "=== comm -3 runs/failed.B.txt runs/failed.$c.txt (col 1 = B-only, col 2 = $c-only) ==="
    comm -3 "$ROOT/runs/failed.B.txt" "$ROOT/runs/failed.$c.txt" | sed 's/^/  /'
    [ -s "$ROOT/runs/failed.$c.txt" ] && echo "  -> $(wc -l < "$ROOT/runs/failed.$c.txt") failing target(s) in $c" \
      || echo "  -> empty diff AND empty failed list for $c? see runs/completeness.$c.txt"
    true
  done
fi

# The one-page view of the results — every cell's numbers, its failing
# targets named, and the A/B verdict (also written to runs/SUMMARY.md).
"$ROOT/harness/summary.sh"

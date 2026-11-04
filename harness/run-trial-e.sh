#!/usr/bin/env bash
#
# run-trial-e.sh — run trial T-e (hypotheses.md): linux + clang, ad hoc.
# Not a cell: five cells are fixed; this produces runs/T-e-* artifacts only.
# Environment = cell B (commit + reference image) plus Containerfile.trial-clang's
# single delta (clang-14 instead of gcc). Separate volumes so cells A/B untouched.
#
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=cells.env
source "$ROOT/harness/cells.env"

[ $# -ge 1 ] && COMMIT=$1 || COMMIT=$(cell_commit B)
IMG=dreal-trial-clang:22.04
SRC_VOL=dreal-trial-clang-src
BAZEL_VOL=dreal-trial-clang-bazel

podman build -t "$IMG" -f "$ROOT/harness/Containerfile.trial-clang" "$ROOT" >&2
podman volume exists "$SRC_VOL" 2>/dev/null || podman volume create "$SRC_VOL" >/dev/null
podman volume exists "$BAZEL_VOL" 2>/dev/null || podman volume create "$BAZEL_VOL" >/dev/null

git -C "$ROOT/dreal4" archive --format=tar "$COMMIT" |
  podman run --rm -i -v "$SRC_VOL":/work "$IMG" \
    bash -c 'rm -rf /work/src && mkdir -p /work/src && tar -xf - -C /work/src'

NAME=dreal-trial-clang
podman rm -f "$NAME" >/dev/null 2>&1 || true
podman run -d --name "$NAME" \
  -v "$SRC_VOL":/work -v "$BAZEL_VOL":/root/.cache/bazel \
  "$IMG" /usr/local/bin/dreal-cell-test >/dev/null
podman wait "$NAME" >/dev/null

mkdir -p "$ROOT/runs"
podman run --rm -v "dreal-trial-clang-src":/work:ro -v "$ROOT/runs":/out "$IMG" \
  bash -c '
    sort -u /work/failed.txt        > /out/T-e-failed.txt
    cp /work/flaky.txt              /out/T-e-flaky.txt
    cp /work/bazel-test.log         /out/T-e-bazel-test.log
    cp /work/exit-code.txt          /out/T-e-exit-code.txt
    cp /work/completeness.txt       /out/T-e-completeness.txt'
podman rm -f "$NAME" >/dev/null 2>&1 || true

echo "T-e collected:"
sed 's/^/  /' "$ROOT/runs/T-e-completeness.txt"
sort -u "$ROOT/runs/failed.B.txt" > /tmp/b-expected.txt
echo "  diff vs cell B's failing set (left=B-only, right=T-e-only):"
comm -3 /tmp/b-expected.txt "$ROOT/runs/T-e-failed.txt" | sed 's/^/    /'

#!/usr/bin/env bash
#
# The one test driver, used identically by every cell:
#   * pristine checkout of the pinned commit   (a volume mount for container
#     cells via run-cell.sh; the clean, pinned submodule itself for host cells)
#   * Bazel cache on its own volume/base, one per cell
#
# usage: test-driver.sh [WORK_DIR] [SRC_DIR]
#   WORK_DIR  where artifacts land           (default /work — container cells)
#   SRC_DIR   the checkout under test        (default $WORK_DIR/src)
#
# Machine budget: the podman machine is shared by cells running in parallel
# (8 CPU / 12 GiB total, halved per cell) — these flags are part of the
# measured configuration; a host cell runs them verbatim too so the parser
# inputs are shaped the same way.
# Results land in WORK_DIR:
#   bazel-test.log     full `bazel test` output (oracle: per-target lines)
#   failed.txt         sorted unique labels with a non-passing status
#   flaky.txt         labels that retried -> PASSED (recorded, not failed)
#   completeness.txt   "Executed N out of M" + loading-error check
#   exit-code.txt      bazel's exit status
#
set -uo pipefail

WORK=${1:-/work}
SRC=${2:-$WORK/src}
cd "$SRC"

rc=0
# --cache_test_results=no: every test must actually re-execute — replaying a
# cached FAILED (known timing flake //dreal/util:timer_test) would fake a
# deterministic result. Tests are fast; the compilation cache does stay warm.
bazel --host_jvm_args=-Xmx1500m test -k --cache_test_results=no \
  --jobs=4 --local_cpu_resources=4 --local_ram_resources=6000 \
  //... 2>&1 | tee "$WORK/bazel-test.log" || rc=$?

# Summary-table lines look like:  //dreal/test:foo    FAILED in 1.02s
# With -k, targets that could not even build show:      NO STATUS
# Anchored on $1 starting with "//": mid-log gtest output also contains
# "[  FAILED  ] ..." and " 1 FAILED TEST" lines, which an unanchored match
# wrongly recorded as labels (parser bug, first run).
awk '$1 ~ /^\/\// && ($2=="FAILED" || $2=="TIMEOUT" || ($2=="NO" && $3=="STATUS")) {print $1}' \
    "$WORK/bazel-test.log" | sort -u > "$WORK/failed.txt"
awk '$1 ~ /^\/\// && $2=="FLAKY" {print $1}' \
    "$WORK/bazel-test.log" | sort -u > "$WORK/flaky.txt"

# Completeness record — an EMPTY failed list only means "all green" together
# with "everything actually ran". Loading-phase errors drop targets without
# leaving a NO STATUS row (they vanished from "Executed N out of M"), which
# is exactly how run 1 silently lost ~259 targets to the gmp probe.
{
  grep -E 'Executed [0-9]+ out of [0-9]+ tests' "$WORK/bazel-test.log" | tail -1 \
    || echo 'NO BAZEL SUMMARY LINE'
  if grep -qE 'loading phase errors|failed to fetch|Failed to locate' "$WORK/bazel-test.log"; then
    echo 'LOADING ERRORS: targets were dropped from this run'
    grep -E '^ERROR:' "$WORK/bazel-test.log" | head -5
  else
    echo 'no loading errors'
  fi
  if grep -qE '^ERROR: Build did NOT complete' "$WORK/bazel-test.log"; then
    echo 'BUILD DID NOT COMPLETE — failed-to-build targets never got a status row'
  fi
} > "$WORK/completeness.txt"

echo "$rc" > "$WORK/exit-code.txt"
cat "$WORK/completeness.txt"
echo "bazel exited with rc=$rc — $(wc -l < "$WORK/failed.txt") failing targets"
exit "$rc"

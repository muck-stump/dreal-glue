#!/usr/bin/env bash
#
# The one test driver, used identically by every cell:
#   * pristine checkout of the pinned commit at /work/src   (made by run-cell.sh)
#   * Bazel cache on its own volume, one per cell           (made by run-cell.sh)
#
# Machine budget: the podman machine is shared by both cells running in
# parallel (8 CPU / 12 GiB total), so jobs and JVM heap are halved per cell.
# Results land next to the source volume:
#   /work/bazel-test.log     full `bazel test` output (oracle: per-target lines)
#   /work/failed.txt         sorted unique labels with a non-passing status
#   /work/flaky.txt          labels that retried -> PASSED (recorded, not failed)
#   /work/exit-code.txt      bazel's exit status
#
set -uo pipefail

cd /work/src

rc=0
# --cache_test_results=no: every test must actually re-execute — replaying a
# cached FAILED (known timing flake //dreal/util:timer_test) would fake a
# deterministic result. Tests are fast; the compilation cache does stay warm.
bazel --host_jvm_args=-Xmx1500m test -k --cache_test_results=no \
  --jobs=4 --local_cpu_resources=4 --local_ram_resources=6000 \
  //... 2>&1 | tee /work/bazel-test.log || rc=$?

# Summary-table lines look like:  //dreal/test:foo    FAILED in 1.02s
# With -k, targets that could not even build show:      NO STATUS
# Anchored on $1 starting with "//": mid-log gtest output also contains
# "[  FAILED  ] ..." and " 1 FAILED TEST" lines, which an unanchored match
# wrongly recorded as labels (parser bug, first run).
awk '$1 ~ /^\/\// && ($2=="FAILED" || $2=="TIMEOUT" || ($2=="NO" && $3=="STATUS")) {print $1}' \
    /work/bazel-test.log | sort -u > /work/failed.txt
awk '$1 ~ /^\/\// && $2=="FLAKY" {print $1}' \
    /work/bazel-test.log | sort -u > /work/flaky.txt

# Completeness record — an EMPTY failed list only means "all green" together
# with "everything actually ran". Loading-phase errors drop targets without
# leaving a NO STATUS row (they vanished from "Executed N out of M"), which
# is exactly how run 1 silently lost ~259 targets to the gmp probe.
{
  grep -E 'Executed [0-9]+ out of [0-9]+ tests' /work/bazel-test.log | tail -1 \
    || echo 'NO BAZEL SUMMARY LINE'
  if grep -qE 'loading phase errors|failed to fetch|Failed to locate' /work/bazel-test.log; then
    echo 'LOADING ERRORS: targets were dropped from this run'
    grep -E '^ERROR:' /work/bazel-test.log | head -5
  else
    echo 'no loading errors'
  fi
} > /work/completeness.txt

echo "$rc" > /work/exit-code.txt
cat /work/completeness.txt
echo "bazel exited with rc=$rc — $(wc -l < /work/failed.txt) failing targets"
exit "$rc"

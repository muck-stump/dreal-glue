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
bazel --host_jvm_args=-Xmx1500m test -k \
  --jobs=4 --local_cpu_resources=4 --local_ram_resources=6000 \
  //... 2>&1 | tee /work/bazel-test.log || rc=$?

# Summary-table lines look like:  //dreal/test:foo    FAILED in 1.02s
# With -k, targets that could not even build show:      NO STATUS
awk '$2=="FAILED" || $2=="TIMEOUT" || ($2=="NO" && $3=="STATUS") {print $1}' \
    /work/bazel-test.log | sort -u > /work/failed.txt
awk '$2=="FLAKY" {print $1}' /work/bazel-test.log | sort -u > /work/flaky.txt

echo "$rc" > /work/exit-code.txt
echo "bazel exited with rc=$rc — $(wc -l < /work/failed.txt) failing targets"
exit "$rc"

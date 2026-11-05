#!/usr/bin/env bash
#
# isolation/run.sh — build and run the ibex isolation test (no dreal code).
#
#   isolation/run.sh                      # here (pkg-config's ibex)
#   isolation/run.sh --dreal PATH         # + show the dreal-level symptom on
#                                         #   isolation/wrong_unsat.smt2
#   isolation/run.sh --container[=IMAGE]  # rebuild & rerun inside the Linux
#                                         # reference cell image (default
#                                         # localhost/dreal-ref:22.04)
#
# Env knobs: CXX, CXXFLAGS (extra, before ibex copts), TEST_CXXFLAGS (append
#           AFTER ibex copts — use it to evaluate fix candidates such as
#           -D__STDC_IEC_559__, the selector is compile-time), IBEX_PREFIX
#           (ibex install prefix), CONTAINER_ENGINE (podman|docker).
#
# Exit code: 0 = every check passed on this system, 1 = ≥1 check failed.
# Expected: macOS / cell C red on [2][3][4] (that failure IS the 22-test
# cluster), Linux cells green on everything.  See README.md.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
src="$here/ibex_rounding_isolation_test.cc"

DMODE=""
IMAGE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dreal) DMODE=${2:?usage: --dreal PATH}; shift 2 ;;
    --container=*) IMAGE=${1#--container=}; shift ;;
    --container)
      if [ $# -ge 2 ] && [ "${2#--}" = "$2" ]; then IMAGE=$2; shift 2
      else IMAGE=localhost/dreal-ref:22.04; shift; fi ;;
    *) echo "run.sh: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

# ---- container mode: re-enter this script inside the Linux image -------
if [ -n "$IMAGE" ]; then
  engine=${CONTAINER_ENGINE:-podman}
  echo "== container mode: $engine run $IMAGE =="
  tar -C "$here" -cf - ibex_rounding_isolation_test.cc run.sh wrong_unsat.smt2 |
    "$engine" run --rm -i "$IMAGE" bash -ec 'mkdir -p /t && cd /t && tar -xf - && chmod +x run.sh && exec ./run.sh'
  exit $?
fi

if [ -z "${CXX:-}" ]; then
  if command -v clang++ >/dev/null 2>&1; then CXX=clang++
  elif command -v g++ >/dev/null 2>&1; then CXX=g++
  else CXX=c++; fi
fi

ibex_flags() {
  if [ -n "${IBEX_PREFIX:-}" ]; then
    PKG_CONFIG_PATH="$IBEX_PREFIX/share/pkgconfig:$IBEX_PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
      pkg-config --cflags --libs ibex
    return 0
  fi
  if pkg-config --exists ibex 2>/dev/null; then
    pkg-config --cflags --libs ibex
    return 0
  fi
  # cell images source-build ibex at this prefix (pkg-config not on PATH)
  if [ -f /opt/libibex/2.7.4/include/ibex.h ]; then
    echo "-frounding-math -I/opt/libibex/2.7.4/include -I/opt/libibex/2.7.4/include/ibex -I/opt/libibex/2.7.4/include/ibex/3rd -L/opt/libibex/2.7.4/lib -libex -lm"
    return 0
  fi
  echo "run.sh: ibex not found — set IBEX_PREFIX or install it (pkg-config 'ibex')" >&2
  exit 2
}

# shellcheck disable=SC2046
flags=$(ibex_flags)
IBEX_PC_VERSION=$(pkg-config --modversion ibex 2>/dev/null || true)
# Every -L we link against is also where the shared lib lives at runtime
# (cell images keep libibex.so outside the loader's default path).
libdirs=""
for f in $flags; do
  case "$f" in -L*) libdirs="$libdirs:${f#-L}" ;; esac
done
[ -n "$libdirs" ] && export LD_LIBRARY_PATH="$libdirs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT

set +e
# shellcheck disable=SC2086
"$CXX" -std=c++11 -O0 -g "$src" -o "$build_dir/ibex_isolation_test" \
  ${CXXFLAGS:-} $flags ${TEST_CXXFLAGS:-} ${LDFLAGS:-}
build_rc=$?
set -e
[ $build_rc -eq 0 ] || exit $build_rc

echo "== isolation test: $CXX, ibex version ${IBEX_PC_VERSION:-?} =="
set +e
"$build_dir/ibex_isolation_test"
rc=$?
set -e

# ---- optional dreal-level symptom (fixture only; the test is ibex-only) -
if [ -n "$DMODE" ]; then
  echo
  echo "== dreal-level cross-check ($DMODE) on wrong_unsat.smt2 =="
  out=$("$DMODE" "$here/wrong_unsat.smt2" | head -1 || true)
  echo "dreal answered: $out"
  if [ "$out" = "unsat" ]; then
    echo "[FAIL] dreal-wrong-unsat — the wrong answer the cluster shows"
    rc=1
  else
    echo "[PASS] dreal answered delta-sat"
  fi
fi

exit $rc

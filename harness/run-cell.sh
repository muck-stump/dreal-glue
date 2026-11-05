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

# Host cell: no image — the checkout under test is the submodule itself,
# run bare on this machine with the same shared driver, artifacts staged in
# runs/ where collect.sh harvests them like any cell volume.
if [ "$(cell_kind "$CELL")" = host ]; then
  HEAD_SHA=$(git -C "$ROOT/dreal4" rev-parse HEAD)
  [ "$HEAD_SHA" = "$COMMIT" ] || {
    echo "cell $CELL: dreal4 HEAD $HEAD_SHA != pinned commit $COMMIT" >&2; exit 1; }

  # Cell C ibex — round-8 default (report.md round 8): the selector-patched
  # source build (harness/install-ibex.sh + IBEX_FORCE_IEC559=1, receipt:
  # runs/T-m-gate.txt) = the 445/445 configuration. Setting
  # CELL_C_IBEX_PREFIX overrides it; setting it EMPTY restores the round-6
  # base config (stock Homebrew ibex@2.7.4_13 -> the frozen 423/22). Dreal's
  # @ibex rule takes PKG_CONFIG_PATH only from dreal4/dreal/workspace.bzl's
  # committed list but tracks PATH (the pkg-config binary it resolves), so
  # with a prefix we prepend harness/shim-bin/pkg-config — whose REQUIRED
  # IBEX_PC_DIR fails loudly, never a silent fallback — and restart the bazel
  # server below so PATH actually reaches the rule.
  IBEX_QUERY="stock PATH pkg-config (opt-out base config: Homebrew ibex@2.7.4_13)"
  RECIPE_C="IBEX_FORCE_IEC559=1 PREFIX=\"$CELL_C_IBEX_PREFIX\" WAF_PY=/opt/homebrew/bin/python3.10 harness/install-ibex.sh"
  if [ -n "${CELL_C_IBEX_PREFIX:-}" ]; then
    IBEX_PC_DIR_C="$CELL_C_IBEX_PREFIX/share/pkgconfig"
    [ -f "$IBEX_PC_DIR_C/ibex.pc" ] || {
      echo "cell $CELL: no ibex.pc at $IBEX_PC_DIR_C" >&2
      echo "  build it:  $RECIPE_C" >&2
      exit 1; }
    # Selector check (fail loudly, same philosophy as the shim): the default
    # region must hold the UNTAPED force-define, not the shipped commented-out
    # one — a prefix built without IBEX_FORCE_IEC559=1 reproduces the frozen
    # 22 cluster (trial-4/5: 0/22 flips) and must not masquerade as the default.
    CFG_C="$CELL_C_IBEX_PREFIX/include/ibex/3rd/rounding_control/rounding_control_config.hpp"
    if [ "${CELL_C_IBEX_ACCEPT_UNPATCHED:-0}" != 1 ]; then
      [ -f "$CFG_C" ] || {
        echo "cell $CELL: no selector header at $CFG_C" >&2
        echo "  build it:  $RECIPE_C" >&2
        exit 1; }
      grep -A1 "ISO C99 rounding functions" "$CFG_C" |
        grep -q "#if ! defined(__STDC_IEC_559__)" || {
        echo "cell $CELL: $CFG_C still has the force-define COMMENTED OUT" >&2
        echo "  that prefix answers ibex's void strategy -> frozen 22 cluster on this Mac" >&2
        echo "  build the default:  $RECIPE_C" >&2
        echo "  (or CELL_C_IBEX_ACCEPT_UNPATCHED=1 to run a deliberate un-patched experiment)" >&2
        exit 1; }
    fi
    export IBEX_PC_DIR="$IBEX_PC_DIR_C"
    export PATH="$ROOT/harness/shim-bin:$PATH"
    IBEX_QUERY="harness/shim-bin/pkg-config (selector-patched prefix: $CELL_C_IBEX_PREFIX)"
  fi
  # Trial hook: substitute the C++ toolchain (hypotheses.md T-d): CELL_CC/CELL_CXX
  # become CC/CXX for bazel's cc autoconfigure; the server restart below gives
  # the (tracked) env to the repository rules.
  [ -n "${CELL_CC:-}" ] && { export CC="$CELL_CC" CXX="${CELL_CXX:-}"; echo "  trial toolchain: CC=$CC CXX=${CXX:-}"; }
  # Trial hook (hypotheses.md T-b/…): extra bazel CLI args, host cell only,
  # passed through from the invoking shell — normal runs pass none.
  export BAZEL_EXTRA_ARGS="${CELL_BAZEL_EXTRA_ARGS:-}"
  [ -n "${CELL_BAZEL_EXTRA_ARGS:-}" ] && echo "  trial extra bazel args: $CELL_BAZEL_EXTRA_ARGS"
  (cd "$ROOT/dreal4" && bazel shutdown >/dev/null 2>&1) || true

  STAGE="$ROOT/runs/.stage-$CELL"
  rm -rf "$STAGE"; mkdir -p "$STAGE"
  # Record *which* ibex this run resolved (thru the shim) — the evidence that
  # the swap is in effect, harvested by collect.sh into runs/ibex.<cell>.txt.
  {
    echo "# cell $CELL ibex resolution ($IBEX_QUERY)"
    if [ -n "${IBEX_PC_DIR:-}" ]; then echo "IBEX_PC_DIR=$IBEX_PC_DIR"; fi
    echo "modversion: $(pkg-config --modversion ibex 2>&1 || true)"
    echo "libs:       $(pkg-config --libs ibex 2>&1 || true)"
  } > "$STAGE/ibex.txt"
  echo "cell $CELL (host): testing $HEAD_SHA at $ROOT/dreal4"
  rc=0
  "$ROOT/harness/test-driver.sh" "$STAGE" "$ROOT/dreal4" || rc=$?
  echo "cell $CELL finished (bazel rc=$rc) — now: harness/collect.sh $CELL"
  exit 0
fi

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

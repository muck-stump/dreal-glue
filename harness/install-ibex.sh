#!/usr/bin/env bash
#
# Source-built ibex for the reference environment (runs inside the image build).
#
# Why: ppa:dreal/dreal ships libibex-dev for amd64 only — the PPA's
# dists/jammy/main/binary-arm64/Packages index is literally empty (20 bytes),
# so `apt-get install libibex-dev` cannot work on arm64. This is the README's
# anticipated fallback ("build ibex 2.7.4 from its release tarball").
#
# Which source: dreal-deps/ibex-lib @ 352eeeb — the *same commit the amd64
# PPA package was built from* (its version string is
# 2.7.4.20220710...git352eeeb2345fb2b7a7ec248b44770d8cdc4a5d67~22.04) and the
# same commit Dockerfile.amazonlinux builds from source into the exact prefix
# dreal/workspace.bzl probes on Linux: /opt/libibex/2.7.4.
# (cell C's mac formula pins tag ibex-2.7.4_13 = commit 26eeeaa, 2021 — a
# different snapshot of the same 2.7.4 line; a B-vs-C attribution detail,
# recorded in harness/NOTES.md.)
#
# Reusable wherever PREFIX/IBEX_CSTDINT_FIX/WAF_PY point it — including
# building cell C's ibex from THIS commit on macOS, where the prefix is
# passed in (see CELL_C_IBEX_PREFIX in cells.env) and resolved not by the
# committed pkg_config_paths list but by harness/shim-bin/pkg-config:
#   PREFIX="${CELL_C_IBEX_PREFIX:-}" … is invoked as
#   PREFIX=~/.local/opt/ibex-352eeeb WAF_PY=/opt/homebrew/bin/python3.10 harness/install-ibex.sh
#
set -euo pipefail

# Interpreter for ibex's bundled waf (shebang is `python3`): waf 2.0.12 does
# `import imp`, removed in CPython 3.12. Default = plain python3, which on
# the Ubuntu images is 3.10 — i.e. exactly the previous behavior. The Fedora
# image sets WAF_PY=python3.10 explicitly (its default python3 is 3.14), so
# the *build tool* is the same interpreter version everywhere; the artifact is
# compiled C++ either way.
WAF_PY=${WAF_PY:-python3}

IBEX_COMMIT=352eeeb2345fb2b7a7ec248b44770d8cdc4a5d67
# sha256 of https://codeload.github.com/dreal-deps/ibex-lib/tar.gz/$IBEX_COMMIT
IBEX_SHA256=4e551e2db7074329d716752b03ee8fed9e685d757c9e26773f0a80d8b45c0763
PREFIX=${PREFIX:-/opt/libibex/2.7.4}

workdir="$(mktemp -d)"
cd "$workdir"

# wget in the images; macOS ships curl instead — same URL, same bytes.
if command -v wget >/dev/null; then
  wget -q -O ibex.tar.gz "https://codeload.github.com/dreal-deps/ibex-lib/tar.gz/${IBEX_COMMIT}"
else
  curl -fsSL -o ibex.tar.gz "https://codeload.github.com/dreal-deps/ibex-lib/tar.gz/${IBEX_COMMIT}"
fi
# digest-and-compare: macOS's sha256sum doesn't do GNU-style `-c` on stdin
actual_sha=$(shasum -a 256 ibex.tar.gz 2>/dev/null | cut -d' ' -f1 \
             || sha256sum ibex.tar.gz | cut -d' ' -f1)
[ "$actual_sha" = "$IBEX_SHA256" ] || {
  echo "sha256 mismatch for ibex.tar.gz: $actual_sha != $IBEX_SHA256" >&2; exit 1; }
tar xzf ibex.tar.gz --strip-components=1

# Portability gate (opt-in, so the reference images keep building exactly
# what they always did): GCC >= 13'"'"'s libstdc++ stopped dragging
# <cstdint> in transitively, and ibex 2.7.4 (2022) uses uint32_t without
# including it — measured: gcc-15/Fedora 43 dies with 6 errors ("uint32_t
# was not declared", plus cascade in ibex_CovSolverData.cpp). Adding the
# include to the two spots gcc complains about is the minimal, upstream-
# style fix; build-affecting only, never test-affecting. Enabled per image via
# IBEX_CSTDINT_FIX=1.
if [ "${IBEX_CSTDINT_FIX:-0}" = 1 ]; then
  echo "IBEX_CSTDINT_FIX=1: adding <cstdint> includes (GCC >= 13 transitive-include breakage)"
  # portable prepend (BSD sed has no GNU `1i\\` line-insert form)
  for f in src/data/ibex_Cov.h plugins/solver/src/ibex_CovSolverData.cpp; do
    printf '#include <cstdint>\n' | cat - "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  done
fi

# Selector gate (opt-in; darwin trials only — the reference images never set
# it. Hypothesis ledger T-m, mechanism read K.)
# filing path: ibex fetches filib as the *bundled tarball*
# plugins/interval_lib_filib/3rd/filibsrc-3.0.2.2.tar.gz whose
# rounding_control/rounding_control_config.hpp.in is an autoconf template the
# filib configure step renders; ibex applies every 3rd/<name>.all.all*patch it
# finds beside that archive *between extraction and compilation* (see
# ibexutils.py apply_all_relevant_patches). The template carries ibex/filib's
# own force-define of __STDC_IEC_559__ **commented out** — and that macro is
# the selector rounding_control_double.hpp reads: defined -> …_iso9x.icc
# (fesetround dance, rigorous outward rounding), never defined -> …_void.icc
# (downward() {} = NOP). No toolchain header chain on darwin ever defines it
# (K: mac 0/0 vs linux 1/1 — runs/K-mechanism.txt), so every darwin ibex
# build — every commit, compiler and cflags variant measured — compiled the
# void strategy and rounded interval endpoints to nearest: root cause of
# cell C's 22-test wrong-unsat cluster.
# So this knob generates a template-side patch file (a sibling of ibex's own
# bundled .all.all.patch) that untapes the three lines — no new arithmetic,
# only a selection between ibex's own two strategies, through ibex's own
# patch pipeline. The block keeps its `#if ! defined(...)` guard, so where the
# macro exists natively (every Linux build) the generated content is
# byte-identical — a reference image with the env set would build the same.
# Receipts before a cell run is trusted:
#   grep config header          (force-define present)
#   nm -u "$PREFIX"/lib/libibex* | grep fesetround  (unpatched darwin: 0 refs)
#   IBEX_PREFIX="$PREFIX" isolation/run.sh          (expects 4/4 green)
if [ "${IBEX_FORCE_IEC559:-0}" = 1 ]; then
  echo "IBEX_FORCE_IEC559=1: generating a patch that untapes ibex/filib's force-define (selects iso9x, rigorous rounding)"
  ARCHIVE="plugins/interval_lib_filib/3rd/filibsrc-3.0.2.2.tar.gz"
  PATCH="plugins/interval_lib_filib/3rd/filibsrc-3.0.2.2.all.all.iec559.patch"
  test -f "$ARCHIVE" || { echo "IBEX_FORCE_IEC559: $ARCHIVE not found" >&2; exit 1; }
  ARCHIVE="$ARCHIVE" PATCH="$PATCH" "${WAF_PY}" - <<'PYEOF'
import difflib
import os
import sys
import tarfile

member = "filibsrc-3.0.2.2/rounding_control/rounding_control_config.hpp.in"
old = "/*\n#if ! defined(__STDC_IEC_559__)\n#define __STDC_IEC_559__\n#endif\n*/\n"
new = "#if ! defined(__STDC_IEC_559__)\n#define __STDC_IEC_559__\n#endif\n"
archive = os.environ["ARCHIVE"]
out = os.environ["PATCH"]
with tarfile.open(archive) as tf:
    raw = tf.extractfile(member).read().decode("utf-8")
if old not in raw:
    print("IBEX_FORCE_IEC559: selector block not found verbatim in", member,
          file=sys.stderr)
    sys.exit(1)
text = ("diff --git a/{0} b/{0}\n".format(member) + "".join(
    difflib.unified_diff(raw.splitlines(True), raw.replace(old, new, 1).splitlines(True),
                         fromfile="a/" + member, tofile="b/" + member, n=3)))
with open(out, "w") as f:
    f.write(text)
print("IBEX_FORCE_IEC559: patch written:", out, "(%d bytes)" % len(text))
PYEOF
fi

# Configure/build exactly as Dockerfile.amazonlinux does (upstream's own
# source-build reference). System clp from Ubuntu's coinor-libclp-dev is
# found via pkg-config (verified: /usr/lib/<triplet>/pkgconfig/clp.pc), so
# ibex does not fall back to building its bundled Clp tarball.
# On gcc-11/aarch64: -frounding-math and -ffloat-store compile (configure
# probes pass), -msse3 fails but the wscript probes it mandatory=False with
# -msse2/plain fallbacks — verified safe.
CXXFLAGS="${CXXFLAGS:--std=c++0x}" "$WAF_PY" ./waf configure \
    --enable-shared --with-optim --with-solver --with-affine-extended \
    --interval-lib=filib --lp-lib=clp --prefix="${PREFIX}"
"$WAF_PY" ./waf install

# arm64: strip the x86-only flags that ibex.pc.in bakes in unconditionally
# (identical fix to cell C's Homebrew formula — "Patch 3: drop x86-only
# flags from ibex.pc on arm64"). aarch64 g++ hard-errors on -msse3, and cell
# C removed -ffloat-store too, keeping B and C consistent.
PC="${PREFIX}/share/pkgconfig/ibex.pc"
# portable in-place (BSD sed's -i wants a suffix arg; GNU's doesn't take one)
sed -e 's/ -msse3//g; s/ -ffloat-store//g' "${PC}" > "${PC}.tmp"
mv "${PC}.tmp" "${PC}"

# macOS only: waf installs the dylib keeping its *build-tree* install name
# (/var/folders/.../__build__/src/libibex.dylib — a temp dir macOS eventually
# purges: the resulting binaries run only until then). Rewrite the id to the
# installed path so every later link against this prefix is self-contained.
if command -v install_name_tool >/dev/null; then
  install_name_tool -id "${PREFIX}/lib/libibex.dylib" "${PREFIX}/lib/libibex.dylib"
fi

# Sanity: exactly the probe dreal/workspace.bzl will run (its Linux entry
# "/opt/libibex/2.7.4/share/pkgconfig"), plus no x86 leftovers.
version="$(PKG_CONFIG_PATH="${PREFIX}/share/pkgconfig" pkg-config --modversion ibex)"
echo "ibex ${version} installed at ${PREFIX}"
test -n "${version}"
! grep -q "msse3" "${PC}"
ls "${PREFIX}"/lib/libibex* >/dev/null

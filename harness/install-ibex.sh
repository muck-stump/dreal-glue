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
PREFIX=/opt/libibex/2.7.4

workdir="$(mktemp -d)"
cd "$workdir"

wget -q -O ibex.tar.gz "https://codeload.github.com/dreal-deps/ibex-lib/tar.gz/${IBEX_COMMIT}"
echo "${IBEX_SHA256}  ibex.tar.gz" | sha256sum -c
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
  sed -i '1i#include <cstdint>' src/data/ibex_Cov.h plugins/solver/src/ibex_CovSolverData.cpp
fi

# Configure/build exactly as Dockerfile.amazonlinux does (upstream's own
# source-build reference). System clp from Ubuntu's coinor-libclp-dev is
# found via pkg-config (verified: /usr/lib/<triplet>/pkgconfig/clp.pc), so
# ibex does not fall back to building its bundled Clp tarball.
# On gcc-11/aarch64: -frounding-math and -ffloat-store compile (configure
# probes pass), -msse3 fails but the wscript probes it mandatory=False with
# -msse2/plain fallbacks — verified safe.
CXXFLAGS=-std=c++0x "$WAF_PY" ./waf configure \
    --enable-shared --with-optim --with-solver --with-affine-extended \
    --interval-lib=filib --lp-lib=clp --prefix="${PREFIX}"
"$WAF_PY" ./waf install

# arm64: strip the x86-only flags that ibex.pc.in bakes in unconditionally
# (identical fix to cell C's Homebrew formula — "Patch 3: drop x86-only
# flags from ibex.pc on arm64"). aarch64 g++ hard-errors on -msse3, and cell
# C removed -ffloat-store too, keeping B and C consistent.
PC="${PREFIX}/share/pkgconfig/ibex.pc"
sed -i 's/ -msse3//g; s/ -ffloat-store//g' "${PC}"

# Sanity: exactly the probe dreal/workspace.bzl will run (its Linux entry
# "/opt/libibex/2.7.4/share/pkgconfig"), plus no x86 leftovers.
version="$(PKG_CONFIG_PATH="${PREFIX}/share/pkgconfig" pkg-config --modversion ibex)"
echo "ibex ${version} installed at ${PREFIX}"
test -n "${version}"
! grep -q "msse3" "${PC}"
ls "${PREFIX}"/lib/libibex* >/dev/null

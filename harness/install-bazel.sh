#!/usr/bin/env bash
#
# Install the pinned Bazel for the reference environment.
#
# Upstream's setup/ubuntu/<ver>/install_prereqs.sh downloads
# bazel_7.0.0-linux-x86_64.deb, but upstream simply does not publish an
# arm64 .deb for 7.0.0 (checked GitHub releases and releases.bazel.build).
# So on arm64 we install the official self-contained
# bazel-7.0.0-linux-arm64 binary (embeds a JDK) instead. This swap is done
# container-side so the checkout under test stays bit-for-bit identical to
# its pinned commit; version and checksums are pinned either way.
#
set -euo pipefail

BAZEL_VERSION=7.0.0

# Arch via uname, not dpkg: Fedora images have no dpkg, and on arm64 (the
# arch this workspace runs) the artifact is distro-independent anyway.
ARCH=$(uname -m)

case "$ARCH" in
  x86_64)
    # Artifact + sha exactly as upstream's install_prereqs.sh pins them —
    # upstream ships no x86_64 rpm either, so this path needs Debian-family.
    command -v dpkg >/dev/null || {
      echo "install-bazel.sh: x86_64 needs dpkg (upstream publishes no rpm for ${BAZEL_VERSION}); use arm64" >&2
      exit 1
    }
    DEB="bazel_${BAZEL_VERSION}-linux-x86_64.deb"
    SHA="e1fd8ffa3cc09bf13b98a69b2b5041cea9d01029112b7e2dbbab5be6f0a3115c"
    wget -q "https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/${DEB}"
    echo "${SHA}  ${DEB}" | sha256sum -c
    dpkg --install ./"${DEB}" || apt-get -f install -y
    rm -f "${DEB}"
    ;;
  aarch64)
    BIN="bazel-${BAZEL_VERSION}-linux-arm64"
    # Official checksum asset published with the release:
    # releases/download/7.0.0/bazel-7.0.0-linux-arm64.sha256
    SHA="cae101d31581a348774526b9d11811b04cc212c943762e6363a85a15bccfca54"
    wget -q -O /usr/local/bin/bazel \
      "https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/${BIN}"
    echo "${SHA}  /usr/local/bin/bazel" | sha256sum -c
    chmod +x /usr/local/bin/bazel
    ;;
  *)
    echo "install-bazel.sh: unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

bazel --version

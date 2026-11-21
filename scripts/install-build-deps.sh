#!/usr/bin/env bash
# Installs the packages the image build needs on the build machine (Ubuntu or Debian).
# The release workflow, the pull request workflow and scripts/Dockerfile all use this one list,
# so a package that a new Ubuntu no longer has shows up in a pull request, not in a release.
#
# Usage: sudo scripts/install-build-deps.sh <arm64|amd64>
set -euo pipefail

ARCH="${1:?usage: install-build-deps.sh <arm64|amd64>}"

case "$ARCH" in
  arm64 | amd64) ;;
  *) echo "install-build-deps.sh: the architecture must be arm64 or amd64" >&2; exit 1 ;;
esac

PACKAGES=(
  # the base system, and the key that proves it comes from Debian.
  # ca-certificates: the base system is downloaded over https.
  debootstrap debian-archive-keyring ca-certificates
  # the disk image: partitions, file systems, loop devices
  parted e2fsprogs dosfstools kpartx udev zerofree
  # tools the build script calls
  sudo psmisc jq gzip
  # the boot loader files of the build machine (build-debian-image.sh copies them for amd64)
  "grub-efi-${ARCH}-bin"
  # the boot test (scripts/boot-test.sh): starts the built image as a virtual machine
  qemu-utils python3 curl
)

case "$ARCH" in
  arm64) PACKAGES+=(qemu-system-arm qemu-efi-aarch64) ;;
  amd64) PACKAGES+=(qemu-system-x86 ovmf) ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends "${PACKAGES[@]}"

# the build stops later without this file, so say it here first
test -s /usr/share/keyrings/debian-archive-keyring.gpg

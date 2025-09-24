#!/bin/bash

# Homebridge VM Image Builder - Local Docker Test Script
# This script detects the architecture, selects the correct Docker image,
# installs required packages, mounts the repo, and runs build.sh for the specified architecture.

set -e

detect_arch() {
  case "$(uname -m)" in
    arm64|aarch64) echo "arm64" ;;
    x86_64) echo "amd64" ;;
    *) echo "amd64" ;;  # fallback to amd64 for unknown architectures
  esac
}

ARCH="${1:-$(detect_arch)}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$ARCH" == "arm64" ]]; then
  DOCKER_IMAGE="arm64v8/ubuntu:24.04"
  GRUB_EFI_PKG="grub-efi-arm64-bin"
elif [[ "$ARCH" == "amd64" ]]; then
  DOCKER_IMAGE="ubuntu:24.04"
  GRUB_EFI_PKG="grub-efi-amd64-bin"
else
  echo "Unsupported architecture: $ARCH"
  exit 1
fi

echo "==> Starting Homebridge VM Image Builder local build for arch: $ARCH"
echo "==> Using Docker image: $DOCKER_IMAGE"
echo "==> Using repo root: $REPO_ROOT"

docker pull "$DOCKER_IMAGE"

docker run --rm -it \
  --privileged \
  -v "$REPO_ROOT":/repo \
  --workdir /repo \
  --name homebridge-vm-test-$ARCH \
  "$DOCKER_IMAGE" bash -c "
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y \
      debootstrap parted e2fsprogs dosfstools \
      $GRUB_EFI_PKG \
      qemu-user-static gzip \
      sudo udev kpartx psmisc
    # sudo udev psmisc are needed for build.sh to work properly inside Docker
    # kpartx is needed, grub-pc-bin was remoted  
    chmod +x ./build.sh
    ./build.sh $ARCH
    ls -lh output/
    echo '==> Build complete. Output files:'
    ls output/
  "

echo "==> Local Docker test finished for arch: $ARCH"
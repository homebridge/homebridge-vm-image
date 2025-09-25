#!/bin/bash

# Homebridge VM Image Builder - Local Docker Test Script
# Simplified to include Dockerfile checksum in the image tag.

set -e

# Detect architecture
detect_arch() {
  case "$(uname -m)" in
    arm64|aarch64) echo "arm64" ;;
    x86_64) echo "amd64" ;;
    *) echo "amd64" ;;  # fallback to amd64 for unknown architectures
  esac
}

ARCH="${1:-$(detect_arch)}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILE="$REPO_ROOT/scripts/Dockerfile"

# Generate a checksum for the Dockerfile
DOCKERFILE_HASH=$(sha256sum "$DOCKERFILE" | awk '{print $1}')

# Use the checksum as part of the image tag
DOCKER_IMAGE_TAG="homebridge-vm-builder-base:$ARCH-$DOCKERFILE_HASH"

if [[ "$ARCH" == "arm64" ]]; then
  BASE_IMAGE="arm64v8/ubuntu:24.04"
  GRUB_EFI_PKG="grub-efi-arm64-bin"
elif [[ "$ARCH" == "amd64" ]]; then
  BASE_IMAGE="ubuntu:24.04"
  GRUB_EFI_PKG="grub-efi-amd64-bin"
else
  echo "Unsupported architecture: $ARCH"
  exit 1
fi

echo "==> Starting Homebridge VM Image Builder local build for arch: $ARCH"
echo "==> Using base image: $BASE_IMAGE"
echo "==> Using Docker image tag: $DOCKER_IMAGE_TAG"
echo "==> Using repo root: $REPO_ROOT"

# Check if the image already exists
if ! docker image inspect "$DOCKER_IMAGE_TAG" > /dev/null 2>&1; then
  echo "==> Dockerfile has changed or image does not exist. Building the Docker image."
  docker build \
    --build-arg BASE_IMAGE="$BASE_IMAGE" \
    --build-arg GRUB_EFI_PKG="$GRUB_EFI_PKG" \
    -t "$DOCKER_IMAGE_TAG" \
    -f "$DOCKERFILE" \
    "$REPO_ROOT"
else
  echo "==> Using cached Docker image: $DOCKER_IMAGE_TAG"
fi

# Run the build
docker run --rm -it \
  --privileged \
  -v "$REPO_ROOT":/repo/ \
  --workdir /repo \
  --name homebridge-vm-test-$ARCH \
  "$DOCKER_IMAGE_TAG" bash -c "
    set -e
    ./build.sh $ARCH
    ls -lh output/
    echo '==> Build complete. Output files:'
    ls output/
  "

echo "==> Local Docker test finished for arch: $ARCH"
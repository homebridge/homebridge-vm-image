#!/bin/bash

# Homebridge VM Image Builder - Local Docker Test Script
# Simplified to include Dockerfile checksum in the image tag.

set -e

BUILD_START=$(date +%s)
# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
  echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
  echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
  echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
  echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

echo "🧪 Homebridge VM Image Local Test Build"
echo "======================================="

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
  error "Unsupported architecture: $ARCH"
  exit 1
fi

log "==> Starting Homebridge VM Image Builder local build for arch: $ARCH"
log "==> Using base image: $BASE_IMAGE"
log "==> Using Docker image tag: $DOCKER_IMAGE_TAG"
log "==> Using repo root: $REPO_ROOT"

# Check if the image already exists
if ! docker image inspect "$DOCKER_IMAGE_TAG" > /dev/null 2>&1; then
  info "==> Dockerfile has changed or image does not exist. Building the Docker image."
  docker build \
    --build-arg BASE_IMAGE="$BASE_IMAGE" \
    --build-arg GRUB_EFI_PKG="$GRUB_EFI_PKG" \
    -t "$DOCKER_IMAGE_TAG" \
    -f "$DOCKERFILE" \
    "$REPO_ROOT"
else
  info "==> Using cached Docker image: $DOCKER_IMAGE_TAG"
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
ELAPSED=$(($(date +%s) - BUILD_START))
log "==> Elapsed build time: $((ELAPSED/60))m $((ELAPSED%60))s"
log "==> Local Docker test finished for arch: $ARCH"
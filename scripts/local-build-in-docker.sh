#!/bin/bash

# Homebridge VM Image Builder - Local Docker Test Script
# Simplified to include Dockerfile checksum in the image tag.

set -e

BUILD_START=$(date +%s)

echo "🧪 Homebridge VM Image Local Test Build"
echo "======================================="


REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${REPO_ROOT}/scripts/lib.sh"

# Usage: local-build-in-docker.sh [arm64|amd64] [stable|beta|alpha]
ARCH="${1:-$(detect_arch)}"
RELEASE_STREAM="${2:-stable}"
DOCKERFILE="$REPO_ROOT/scripts/Dockerfile"

# Generate a checksum for the Dockerfile and the package list it installs
DOCKERFILE_HASH=$(cat "$DOCKERFILE" "$REPO_ROOT/scripts/install-build-deps.sh" | sha256sum | awk '{print $1}')

# Use the checksum as part of the image tag
DOCKER_IMAGE_TAG="homebridge-vm-builder:${RELEASE_STREAM}-$ARCH-$DOCKERFILE_HASH"

if [[ "$ARCH" == "arm64" ]]; then
  BASE_IMAGE="arm64v8/ubuntu:24.04"
elif [[ "$ARCH" == "amd64" ]]; then
  BASE_IMAGE="ubuntu:24.04"
else
  error "Unsupported architecture: $ARCH"
  exit 1
fi

log "==> Starting Homebridge VM Image Builder local build for release stream ${RELEASE_STREAM} on arch: $ARCH"
log "==> Using base image: $BASE_IMAGE"
log "==> Using Docker image tag: $DOCKER_IMAGE_TAG"
log "==> Using repo root: $REPO_ROOT"

# Check if the image already exists
if ! docker image inspect "$DOCKER_IMAGE_TAG" > /dev/null 2>&1; then
  info "==> Dockerfile has changed or image does not exist. Building the Docker image."
  docker build \
    --build-arg BASE_IMAGE="$BASE_IMAGE" \
    --build-arg ARCH="$ARCH" \
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
  --name "homebridge-vm-build-${RELEASE_STREAM}-${ARCH}" \
  "$DOCKER_IMAGE_TAG" \
  bash ./build-debian-image.sh "$ARCH" "${RELEASE_STREAM}" 

ELAPSED=$(($(date +%s) - BUILD_START))
log "==> Elapsed build time: $((ELAPSED/60))m $((ELAPSED%60))s"
log "==> Local Docker test finished for release stream ${BLUE}${RELEASE_STREAM}${NC} on arch: ${BLUE}${ARCH}${NC}"

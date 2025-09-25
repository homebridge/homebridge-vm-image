#!/usr/bin/env bash

BASH_DEBUG="" # "" or "x" for debugging

set -euo${BASH_DEBUG} pipefail

# VirtualBox Appliance Packaging Script
# Supports multiple release streams: alpha, beta, stable

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Auto-detect architecture based on host system
detect_default_arch() {
  case "$(uname -m)" in
    arm64|aarch64) echo "arm64" ;;
    x86_64) echo "amd64" ;;
    *) echo "amd64" ;;  # fallback to amd64 for unknown architectures
  esac
}

ARCH="${1:-$(detect_default_arch)}"
RELEASE_STREAM="${2:-stable}" # Default to "stable" if not provided

# Validate architecture
if [[ "$ARCH" != "arm64" && "$ARCH" != "amd64" ]]; then
  echo -e "\033[0;31mERROR:\033[0m Unsupported architecture: $ARCH"
  echo "Supported architectures: amd64, arm64"
  exit 1
fi

# Validate release stream
if [[ "$RELEASE_STREAM" != "alpha" && "$RELEASE_STREAM" != "beta" && "$RELEASE_STREAM" != "stable" ]]; then
  echo -e "\033[0;31mERROR:\033[0m Unsupported release stream: $RELEASE_STREAM"
  echo "Supported release streams: alpha, beta, stable"
  exit 1
fi

VM_NAME="homebridge-vm-$ARCH-$RELEASE_STREAM"
VM_RAM="1024"
OUTPUT_DIR="${REPO_ROOT}/output"
IMG_FILE="$OUTPUT_DIR/homebridge-$ARCH-$RELEASE_STREAM.img"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Logging functions
log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARN:${NC} $*" >&2; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $*" >&2; }

extract_manifest() {
  local manifest_file

  if [[ ! -f "$IMG_FILE" ]]; then
    error "IMG file not found: $IMG_FILE"
    exit 1
  fi

  # Look for the manifest file in the same directory as the IMG file
  manifest_file="$(dirname "$IMG_FILE")/homebridge*.manifest"

  if [[ -f $manifest_file ]]; then
    log "📄 Build manifest found: $manifest_file"
    cat "$manifest_file"
  else
    warn "No build manifest found in the same directory as $IMG_FILE"
  fi
}

main() {
  echo "📦 Homebridge VirtualBox Appliance Packaging"
  echo "==========================================="
  log "Release Stream: $RELEASE_STREAM"
  log "Architecture: $ARCH"
  log "Output Directory: $OUTPUT_DIR"

  extract_manifest

  log "🎉 Manifest extraction completed successfully!"
}

main "$@"
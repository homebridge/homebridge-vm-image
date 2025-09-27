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

VM_NAME="homebridge-vm-image-${RELEASE_STREAM}-${ARCH}" 
VM_RAM="1024"
OUTPUT_DIR="${REPO_ROOT}/output"
VMDK_FILE="$OUTPUT_DIR/${VM_NAME}.vmdk"
OVA_FILE="$OUTPUT_DIR/${VM_NAME}.ova"
MANIFEST_FILE="$OUTPUT_DIR/${VM_NAME}.manifest"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Logging functions
log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARN:${NC} $*" >&2; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $*" >&2; }

check_dependencies() {
  log "🔍 Checking dependencies..."
  if ! command -v VBoxManage &> /dev/null; then
    error "VirtualBox is required but not installed"
    echo "Please install VirtualBox: https://www.virtualbox.org/wiki/Downloads"
    exit 1
  fi
  if ! command -v qemu-img &> /dev/null; then
    warn "qemu-img is not installed. Falling back to VBoxManage for image conversion."
  fi
}

convert_image_to_vmdk() {
  local img_gz_file="$OUTPUT_DIR/${VM_NAME}.img.gz"
  local img_file="$OUTPUT_DIR/${VM_NAME}.img"

  if [[ -f "$VMDK_FILE" ]]; then
    log "✅ VMDK file already exists: $VMDK_FILE"
    return
  fi

  if [[ -f "$img_gz_file" ]]; then
    log "📦 Extracting compressed image..."
    gunzip -k "$img_gz_file"
  fi

  if [[ -f "$img_file" ]]; then
    log "🔄 Converting IMG to VMDK..."
    if command -v qemu-img &> /dev/null; then
      qemu-img convert -f raw -O vmdk "$img_file" "$VMDK_FILE"
    else
      VBoxManage convertfromraw "$img_file" "$VMDK_FILE" --format VMDK
    fi
    log "✅ Conversion to VMDK completed: $VMDK_FILE"
  else
    error "No IMG file found for conversion: $img_gz_file or $img_file"
    exit 1
  fi
}

package_as_ova() {
  if [[ -f "$OVA_FILE" ]]; then
    log "✅ OVA file already exists: $OVA_FILE"
    return
  fi

  log "📦 Packaging VirtualBox Appliance (OVA)..."
  VBoxManage createvm --name "$VM_NAME" --register --os-type="Debian12_${ARCH}" --platform-architecture=$( [[ "$ARCH" == "arm64" ]] && echo "arm" || echo "x86" )
  VBoxManage modifyvm "$VM_NAME" \
    --memory "$VM_RAM" \
    --cpus 1 \
    --firmware bios \
    --boot1 disk \
    --nic1 bridged \
    --bridgeadapter1 "en0" \
    --cableconnected1 on \
    --audio none \
    --usb off \
    --graphicscontroller vmsvga \
    --vram 16 \
    --accelerate3d off \
    --mouse usbtablet \
    --keyboard usb

  log "Attaching storage..."
  VBoxManage storagectl "$VM_NAME" --name "SATA" --add sata --controller IntelAhci --portcount 1
  VBoxManage storageattach "$VM_NAME" \
    --storagectl "SATA" \
    --port 0 \
    --device 0 \
    --type hdd \
    --medium "$VMDK_FILE"

  log "Configuring VM settings..."
  VBoxManage modifyvm "$VM_NAME" \
    --clipboard-mode bidirectional \
    --draganddrop bidirectional
  VBoxManage modifyvm "$VM_NAME" \
    --uart1 0x3F8 4 \
    --uartmode1 file "$OUTPUT_DIR/${VM_NAME}.log"
  VBoxManage modifyvm "$VM_NAME" --iconfile "${REPO_ROOT}/assets/homebridge-icon.png"
  VBoxManage modifyvm "$VM_NAME" --os-type="Debian12_${ARCH}"
  VBoxManage modifyvm "$VM_NAME" --description "$(cat ${MANIFEST_FILE})"

  log "Exporting to OVA..."
  VBoxManage export "$VM_NAME" --output "$OVA_FILE"
  VBoxManage unregistervm "$VM_NAME" --delete
  log "✅ OVA packaging completed: $OVA_FILE"
}

main() {
  echo "📦 Homebridge VirtualBox Appliance Packaging"
  echo "==========================================="
  log "Release Stream: $RELEASE_STREAM"
  log "Architecture: $ARCH"
  log "Output Directory: $OUTPUT_DIR"

  check_dependencies
  convert_image_to_vmdk
  package_as_ova

  log "🎉 Packaging completed successfully!"
  echo ""
  echo "✨ OVA Details:"
  echo "  Name: $VM_NAME"
  echo "  Architecture: $ARCH"
  echo "  Release Stream: $RELEASE_STREAM"
  echo "  $(cat ${MANIFEST_FILE}| grep 'Release Version: ')"
  echo "  RAM: ${VM_RAM}MB"
  echo "  OVA File: $OVA_FILE"

  export OVA_FILE=$OVA_FILE
}

main "$@"
#!/usr/bin/env bash

BASH_DEBUG="" # "" or "x" for debugging

set -euo${BASH_DEBUG} pipefail

# Homebridge VM Validation Script
# Compatible with macOS/M1 and Linux systems with VirtualBox

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

# Validate architecture
if [[ "$ARCH" != "arm64" && "$ARCH" != "amd64" ]]; then
  echo -e "\033[0;31mERROR:\033[0m Unsupported architecture: $ARCH"
  echo "Supported architectures: amd64, arm64"
  exit 1
fi
VM_NAME="homebridge-vm-test-$ARCH"
VM_RAM="1024"
OUTPUT_DIR="${REPO_ROOT}/output"
VALIDATION_TIMEOUT=300  # 5 minutes

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARN:${NC} $*" >&2; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $*" >&2; }
info() { echo -e "${BLUE}[$(date +'%H:%M:%S')] INFO:${NC} $*" >&2; }

check_dependencies() {
  log "🔍 Checking dependencies..."
  if ! command -v VBoxManage &> /dev/null; then
    error "VirtualBox is required but not installed"
    echo "Please install VirtualBox: https://www.virtualbox.org/wiki/Downloads"
    exit 1
  fi
  local vbox_version
  vbox_version=$(VBoxManage --version 2>/dev/null || echo "unknown")
  log "✅ VirtualBox version: $vbox_version"
  local host_arch
  host_arch=$(uname -m)
  if [[ "$host_arch" == "arm64" && "$ARCH" == "amd64" ]]; then
    error "Architecture mismatch: Cannot run AMD64/x86 VMs on ARM64 hardware"
    echo "💡 Use ARM64 image instead."
    exit 1
  elif [[ "$host_arch" == "x86_64" && "$ARCH" == "arm64" ]]; then
    warn "Running ARM64 VM on x86_64 host - performance may be limited"
  fi
  local vmdk_file="$OUTPUT_DIR/homebridge-$ARCH.vmdk"
  local img_gz_file="$OUTPUT_DIR/homebridge-$ARCH.img.gz"
  local raw_file="$OUTPUT_DIR/homebridge-$ARCH.raw"
  local img_file="$OUTPUT_DIR/homebridge-$ARCH.img"
  if [[ -f "$vmdk_file" ]]; then
    log "✅ VMDK image found: $vmdk_file"
  elif [[ -f "$img_gz_file" || -f "$img_file" ]]; then
    warn "VMDK not found, but IMG found. Converting..."
    convert_image_format
  elif [[ -f "$raw_file" ]]; then
    warn "VMDK not found, but RAW image found. Converting..."
    convert_raw_to_vmdk
  else
    error "No compatible VM image found in $OUTPUT_DIR/"
    echo "Expected one of:"
    echo "  - $vmdk_file"
    echo "  - $img_gz_file" 
    echo "  - $raw_file"
    echo "Please run build.sh first"
    exit 1
  fi
}

convert_image_format() {
  local img_gz="$OUTPUT_DIR/homebridge-$ARCH.img.gz"
  local img_file="$OUTPUT_DIR/homebridge-$ARCH.img"
  local vmdk_file="$OUTPUT_DIR/homebridge-$ARCH.vmdk"
  if [[ (-f "$img_gz" || -f "$img_file" )&& ! -f "$vmdk_file" ]]; then
    if [[ ! -f "$img_file"  ]]; then
      log "📦 Extracting compressed image..."
      gunzip -k "$img_gz"
    fi
    log "🔄 Converting IMG to VMDK..."
    if command -v qemu-img &> /dev/null; then
      qemu-img convert -f raw -O vmdk "$img_file" "$vmdk_file"
    else
      VBoxManage convertfromraw "$img_file" "$vmdk_file" --format VMDK
    fi
    log "✅ Conversion completed"
  fi
}

convert_raw_to_vmdk() {
  local raw_file="$OUTPUT_DIR/homebridge-$ARCH.raw"
  local vmdk_file="$OUTPUT_DIR/homebridge-$ARCH.vmdk"
  if [[ -f "$raw_file" && ! -f "$vmdk_file" ]]; then
    log "🔄 Converting RAW to VMDK..."
    if command -v qemu-img &> /dev/null; then
      qemu-img convert -f raw -O vmdk "$raw_file" "$vmdk_file"
    else
      VBoxManage convertfromraw "$raw_file" "$vmdk_file" --format VMDK
    fi
    log "✅ RAW to VMDK conversion completed"
  fi
}

cleanup_vm() {
  log "🧹 Cleaning up existing VM..."
  if VBoxManage list runningvms | grep -q "\"$VM_NAME\""; then
    warn "Stopping running VM: $VM_NAME"
    VBoxManage controlvm "$VM_NAME" poweroff || true
    sleep 3
  fi
  if VBoxManage list vms | grep -q "\"$VM_NAME\""; then
    warn "Removing existing VM: $VM_NAME"
    VBoxManage unregistervm "$VM_NAME" || true
    rm -rf ~/VirtualBox\ VMs/"$VM_NAME"
  fi
}

create_vm() {
  log "🖥️  Creating VirtualBox VM..."
  local vmdk_file="$OUTPUT_DIR/homebridge-$ARCH.vmdk"
  local homebridge_data="$OUTPUT_DIR/homebridge-data.vdi"
  local os_type
  case "$ARCH" in
    amd64) os_type="Linux_64" ;;
    arm64) os_type="Debian12_arm64" ;;
    *) os_type="Linux_64" ;;
  esac
  VBoxManage createvm --name "$VM_NAME" --ostype "$os_type" --register
  VBoxManage modifyvm "$VM_NAME" \
    --memory "$VM_RAM" \
    --cpus 1 \
    --firmware bios \
    --boot1 disk \
    --nic1 bridged \
    --bridgeadapter1 "en0" \
    --cableconnected1 on \
    --audio-driver none \
    --usb off \
    --graphicscontroller vmsvga \
    --vram 16 \
    --accelerate3d off \
    --mouse usbtablet \
    --keyboard usb \
    --uart1 0x3F8 4 \
    --uartmode1 file "$OUTPUT_DIR/vm-console-${ARCH}.log"
  VBoxManage storagectl "$VM_NAME" --name "SATA" --add sata --controller IntelAhci --portcount 4
  VBoxManage storageattach "$VM_NAME" \
    --storagectl "SATA" \
    --port 0 \
    --device 0 \
    --type hdd \
    --medium "$vmdk_file"
  if [[ ! -f "$homebridge_data" ]]; then
    log "📁 Creating persistent homebridge data disk..."
    VBoxManage createhd --filename "$homebridge_data" --size 10240
  fi
  VBoxManage storageattach "$VM_NAME" \
    --storagectl "SATA" \
    --port 1 \
    --device 0 \
    --type hdd \
    --medium "$homebridge_data"
  VBoxManage modifyvm "$VM_NAME" \
    --clipboard-mode bidirectional \
    --draganddrop bidirectional
  VBoxManage modifyvm "$VM_NAME" --iconfile "${REPO_ROOT}/assets/homebridge-icon.png"
  log "✅ VM created and configured"
}

start_vm() {
  log "🚀 Starting VM..."
  VBoxManage startvm "$VM_NAME" --type headless
  log "✅ VM started successfully"
}

wait_for_vm_boot() {
  log "⏳ Waiting for VM to boot and services to start..."
  local elapsed=0
  local boot_success=false
  while [[ $elapsed -lt $VALIDATION_TIMEOUT ]]; do
    if ! VBoxManage list runningvms | grep -q "\"$VM_NAME\""; then
      error "VM stopped unexpectedly"
      return 1
    fi
    if curl -s --connect-timeout 5 http://localhost:8581 > /dev/null 2>&1; then
      boot_success=true
      break
    fi
    if [[ $((elapsed % 30)) -eq 0 ]]; then
      info "Still waiting for services... ($elapsed/${VALIDATION_TIMEOUT}s)"
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  if [[ "$boot_success" == "true" ]]; then
    log "✅ VM booted successfully and services are responding"
    return 0
  else
    error "VM failed to boot or services didn't start within ${VALIDATION_TIMEOUT}s"
    return 1
  fi
}

validate_homebridge() {
  log "🔍 Validating Homebridge service..."
  local response_code
  response_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8581 || echo "000")
  if [[ "$response_code" == "200" ]]; then
    log "✅ Homebridge web interface is responding (HTTP $response_code)"
    local content
    content=$(curl -s http://localhost:8581 || echo "")
    if echo "$content" | grep -qi "homebridge"; then
      log "✅ Homebridge UI confirmed in response"
    else
      warn "Response received but Homebridge UI not confirmed"
    fi
  else
    error "Homebridge web interface not responding (HTTP $response_code)"
    return 1
  fi
  if nc -z localhost 51826 2>/dev/null; then
    log "✅ HomeKit service port (51826) is accessible"
  else
    warn "HomeKit service port (51826) not accessible"
  fi
  return 0
}

stop_vm() {
  log "🛑 Stopping VM..."
  if VBoxManage list runningvms | grep -q "\"$VM_NAME\""; then
    VBoxManage controlvm "$VM_NAME" acpipowerbutton
    local elapsed=0
    while [[ $elapsed -lt 30 ]] && VBoxManage list runningvms | grep -q "\"$VM_NAME\""; do
      sleep 2
      elapsed=$((elapsed + 2))
    done
    if VBoxManage list runningvms | grep -q "\"$VM_NAME\""; then
      warn "Force stopping VM"
      VBoxManage controlvm "$VM_NAME" poweroff
    fi
  fi
  log "✅ VM stopped"
}

cleanup_and_exit() {
  local exit_code=$1
  if [[ $exit_code -eq 0 ]]; then
    log "🎉 Validation completed successfully!"
    echo ""
    echo "✨ VM Details:"
    echo "  Name: $VM_NAME"
    echo "  Architecture: $ARCH"
    echo "  RAM: ${VM_RAM}MB"
    echo "  Homebridge UI: http://localhost:8581"
    echo "  HomeKit Port: 51826"
    echo ""
    echo "💡 The VM is left running for re-testing or manual inspection."
    echo "   Start GUI: VBoxManage startvm \"$VM_NAME\" --type gui"
    echo "   Stop VM: VBoxManage controlvm \"$VM_NAME\" acpipowerbutton"
    echo "   Clean up: VBoxManage unregistervm \"$VM_NAME\""
  else
    error "Validation failed!"
    log "🧹 Stopping VM due to validation failure..."
    stop_vm || true
    echo ""
    echo "💡 VM has been stopped. Check logs above for errors."
    echo "   Retry: $0 $ARCH"
    echo "   Clean up: VBoxManage unregistervm \"$VM_NAME\""
  fi
  exit $exit_code
}

main() {
  echo "🧪 Homebridge VM Validation"
  echo "==========================="
  check_dependencies
  cleanup_vm
  create_vm
  start_vm
  if wait_for_vm_boot && validate_homebridge; then
    log "🎉 All validation tests passed!"
    cleanup_and_exit 0
  else
    error "Validation failed!"
    cleanup_and_exit 1
  fi
}

main "$@"
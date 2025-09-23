#!/usr/bin/env bash
set -euo pipefail

# LinuxKit Homebridge VM Validation Script
# Compatible with macOS/M1 and Linux systems with VirtualBox

# Handle help flag first
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  print_usage() {
    echo "Usage: $0 [ARCHITECTURE]"
    echo ""
    echo "Validate Homebridge LinuxKit VM images using VirtualBox"
    echo ""
    echo "Arguments:"
    echo "  ARCHITECTURE    Target architecture (amd64|arm64) [default: amd64]"
    echo ""
    echo "Examples:"
    echo "  $0              # Validate amd64 image"
    echo "  $0 amd64        # Validate amd64 image"
    echo "  $0 arm64        # Validate ARM64 image"
    echo ""
    echo "Requirements:"
    echo "  - VirtualBox"
    echo "  - VM image built with build-linuxkit.sh"
    echo "  - curl (for testing HTTP endpoints)"
    echo "  - nc/netcat (for testing ports)"
  }
  print_usage
  exit 0
fi

ARCH="${1:-amd64}"

# Validate architecture
if [[ "$ARCH" != "arm64" && "$ARCH" != "amd64" ]]; then
  echo -e "${RED}ERROR:${NC} Unsupported architecture: $ARCH"
  echo "Supported architectures: amd64, arm64"
  exit 1
fi
VM_NAME="homebridge-linuxkit-test"
VM_RAM="1024"
OUTPUT_DIR="output"
VALIDATION_TIMEOUT=300  # 5 minutes

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

# Check dependencies
check_dependencies() {
  log "🔍 Checking dependencies..."
  
  # Check VirtualBox
  if ! command -v VBoxManage &> /dev/null; then
    error "VirtualBox is required but not installed"
    echo "Please install VirtualBox: https://www.virtualbox.org/wiki/Downloads"
    exit 1
  fi
  
  # Check VirtualBox version
  local vbox_version
  vbox_version=$(VBoxManage --version 2>/dev/null || echo "unknown")
  log "✅ VirtualBox version: $vbox_version"
  
  # Check if VM image exists
  local image_file="$OUTPUT_DIR/homebridge-$ARCH.vmdk"
  if [[ ! -f "$image_file" ]]; then
    # Try other formats
    if [[ -f "$OUTPUT_DIR/homebridge-$ARCH.img.gz" ]]; then
      warn "VMDK not found, but compressed IMG found. Converting..."
      convert_image_format
    else
      error "VM image not found: $image_file"
      echo "Please run build-linuxkit.sh first"
      exit 1
    fi
  fi
}

convert_image_format() {
  local img_gz="$OUTPUT_DIR/homebridge-$ARCH.img.gz"
  local img_file="$OUTPUT_DIR/homebridge-$ARCH.img"
  local vmdk_file="$OUTPUT_DIR/homebridge-$ARCH.vmdk"
  
  if [[ -f "$img_gz" && ! -f "$vmdk_file" ]]; then
    log "📦 Extracting compressed image..."
    gunzip -k "$img_gz"
    
    log "🔄 Converting IMG to VMDK..."
    VBoxManage convertfromraw "$img_file" "$vmdk_file" --format VMDK
    
    log "✅ Conversion completed"
  fi
}

cleanup_vm() {
  log "🧹 Cleaning up existing VM..."
  
  # Stop VM if running
  if VBoxManage list runningvms | grep -q "\"$VM_NAME\""; then
    warn "Stopping running VM: $VM_NAME"
    VBoxManage controlvm "$VM_NAME" poweroff || true
    sleep 3
  fi
  
  # Remove existing VM
  if VBoxManage list vms | grep -q "\"$VM_NAME\""; then
    warn "Removing existing VM: $VM_NAME"
    VBoxManage unregistervm "$VM_NAME" --delete || true
  fi
}

create_vm() {
  log "🖥️  Creating VirtualBox VM..."
  
  local vmdk_file="$OUTPUT_DIR/homebridge-$ARCH.vmdk"
  local os_type
  
  # Set OS type based on architecture
  case "$ARCH" in
    amd64) os_type="Linux_64" ;;
    arm64) os_type="Linux_64" ;;  # VirtualBox uses same type for both
    *) os_type="Linux_64" ;;
  esac
  
  # Create VM
  VBoxManage createvm --name "$VM_NAME" --ostype "$os_type" --register
  
  # Configure VM
  VBoxManage modifyvm "$VM_NAME" \
    --memory "$VM_RAM" \
    --cpus 1 \
    --firmware efi \
    --boot1 disk \
    --nic1 nat \
    --natpf1 "homebridge,tcp,,8581,,8581" \
    --natpf1 "ssh,tcp,,2222,,22" \
    --natpf1 "homekit,tcp,,51826,,51826"
  
  # Add storage controller
  VBoxManage storagectl "$VM_NAME" --name "SATA" --add sata --controller IntelAhci
  
  # Attach disk
  VBoxManage storageattach "$VM_NAME" \
    --storagectl "SATA" \
    --port 0 \
    --device 0 \
    --type hdd \
    --medium "$vmdk_file"
  
  log "✅ VM created and configured"
}

start_vm() {
  log "🚀 Starting VM..."
  
  # Start VM in headless mode
  VBoxManage startvm "$VM_NAME" --type headless
  
  log "✅ VM started successfully"
}

wait_for_vm_boot() {
  log "⏳ Waiting for VM to boot and services to start..."
  
  local elapsed=0
  local boot_success=false
  
  while [[ $elapsed -lt $VALIDATION_TIMEOUT ]]; do
    # Check if VM is still running
    if ! VBoxManage list runningvms | grep -q "\"$VM_NAME\""; then
      error "VM stopped unexpectedly"
      return 1
    fi
    
    # Try to connect to Homebridge web interface
    if curl -s --connect-timeout 5 http://localhost:8581 > /dev/null 2>&1; then
      boot_success=true
      break
    fi
    
    # Progress indicator
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
  
  # Test web interface
  local response_code
  response_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8581 || echo "000")
  
  if [[ "$response_code" == "200" ]]; then
    log "✅ Homebridge web interface is responding (HTTP $response_code)"
    
    # Get page content to validate
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
  
  # Test HomeKit port
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
    
    # Wait for graceful shutdown
    local elapsed=0
    while [[ $elapsed -lt 30 ]] && VBoxManage list runningvms | grep -q "\"$VM_NAME\""; do
      sleep 2
      elapsed=$((elapsed + 2))
    done
    
    # Force stop if still running
    if VBoxManage list runningvms | grep -q "\"$VM_NAME\""; then
      warn "Force stopping VM"
      VBoxManage controlvm "$VM_NAME" poweroff
    fi
  fi
  
  log "✅ VM stopped"
}

cleanup_and_exit() {
  local exit_code=$1
  
  log "🧹 Performing cleanup..."
  
  # Stop VM
  stop_vm || true
  
  # Optionally remove VM (uncomment if you want to clean up completely)
  # cleanup_vm || true
  
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
    echo "💡 The VM has been stopped but not removed."
    echo "   You can start it again with: VBoxManage startvm \"$VM_NAME\" --type gui"
    echo "   Or remove it with: VBoxManage unregistervm \"$VM_NAME\" --delete"
  else
    error "Validation failed!"
  fi
  
  exit $exit_code
}

print_usage() {
  echo "Usage: $0 [ARCHITECTURE]"
  echo ""
  echo "Validate Homebridge LinuxKit VM images using VirtualBox"
  echo ""
  echo "Arguments:"
  echo "  ARCHITECTURE    Target architecture (amd64|arm64) [default: amd64]"
  echo ""
  echo "Examples:"
  echo "  $0              # Validate amd64 image"
  echo "  $0 amd64        # Validate amd64 image"
  echo "  $0 arm64        # Validate ARM64 image"
  echo ""
  echo "Requirements:"
  echo "  - VirtualBox"
  echo "  - VM image built with build-linuxkit.sh"
  echo "  - curl (for testing HTTP endpoints)"
  echo "  - nc/netcat (for testing ports)"
}

main() {
  echo "🧪 Homebridge LinuxKit VM Validation"
  echo "====================================="
  
  # Set up cleanup trap
  trap 'cleanup_and_exit $?' EXIT
  
  # Validation steps
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
#!/usr/bin/env bash
set -euo pipefail

# LinuxKit VM Cleanup Script
# Cleans up VirtualBox VMs created by validate-linuxkit.sh

# Auto-detect architecture based on host system
detect_default_arch() {
  case "$(uname -m)" in
    arm64|aarch64) echo "arm64" ;;
    x86_64) echo "amd64" ;;
    *) echo "amd64" ;;  # fallback to amd64 for unknown architectures
  esac
}

# Handle help flag first
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  print_usage() {
    echo "Usage: $0 [ARCHITECTURE|all]"
    echo ""
    echo "Clean up Homebridge LinuxKit VMs created by validate-linuxkit.sh"
    echo ""
    echo "Arguments:"
    echo "  ARCHITECTURE    Target architecture (amd64|arm64) [default: auto-detect from host]"
    echo "  all             Clean up all LinuxKit test VMs"
    echo ""
    echo "Examples:"
    echo "  $0              # Clean up host architecture VM ($(detect_default_arch))"
    echo "  $0 amd64        # Clean up AMD64 VM"
    echo "  $0 arm64        # Clean up ARM64 VM"
    echo "  $0 all          # Clean up all LinuxKit test VMs"
    echo ""
    echo "What this script does:"
    echo "  - Stops running LinuxKit test VMs"
    echo "  - Removes VMs from VirtualBox completely"
    echo "  - Cleans up temporary files"
    echo ""
    echo "Requirements:"
    echo "  - VirtualBox"
  }
  print_usage
  exit 0
fi

TARGET="${1:-$(detect_default_arch)}"

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
  if ! command -v VBoxManage &> /dev/null; then
    error "VirtualBox is required but not installed"
    echo "Please install VirtualBox: https://www.virtualbox.org/wiki/Downloads"
    exit 1
  fi
}

stop_vm() {
  local vm_name="$1"
  
  if VBoxManage list runningvms | grep -q "\"$vm_name\""; then
    log "🛑 Stopping VM: $vm_name"
    
    # Try graceful shutdown first
    VBoxManage controlvm "$vm_name" acpipowerbutton || true
    
    # Wait for graceful shutdown
    local elapsed=0
    while [[ $elapsed -lt 30 ]] && VBoxManage list runningvms | grep -q "\"$vm_name\""; do
      sleep 2
      elapsed=$((elapsed + 2))
    done
    
    # Force stop if still running
    if VBoxManage list runningvms | grep -q "\"$vm_name\""; then
      warn "Force stopping VM: $vm_name"
      VBoxManage controlvm "$vm_name" poweroff || true
      sleep 2
    fi
    
    log "✅ VM stopped: $vm_name"
  else
    info "VM not running: $vm_name"
  fi
}

remove_vm() {
  local vm_name="$1"
  
  if VBoxManage list vms | grep -q "\"$vm_name\""; then
    log "🗑️  Removing VM: $vm_name"
    VBoxManage unregistervm "$vm_name" --delete || true
    log "✅ VM removed: $vm_name"
  else
    info "VM not found: $vm_name"
  fi
}

cleanup_vm() {
  local vm_name="$1"
  
  log "🧹 Cleaning up VM: $vm_name"
  stop_vm "$vm_name"
  remove_vm "$vm_name"
}

cleanup_all_linuxkit_vms() {
  log "🧹 Cleaning up all LinuxKit test VMs..."
  
  # List all VMs and find LinuxKit test VMs
  local vm_list
  vm_list=$(VBoxManage list vms 2>/dev/null | grep -E "(homebridge-linuxkit|linuxkit-test)" | cut -d'"' -f2 || true)
  
  if [[ -z "$vm_list" ]]; then
    info "No LinuxKit test VMs found"
    return 0
  fi
  
  echo "Found LinuxKit test VMs:"
  echo "$vm_list" | while read -r vm_name; do
    echo "  - $vm_name"
  done
  
  echo ""
  read -p "Are you sure you want to remove all these VMs? (y/N): " -n 1 -r
  echo
  
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "$vm_list" | while read -r vm_name; do
      if [[ -n "$vm_name" ]]; then
        cleanup_vm "$vm_name"
      fi
    done
    log "✅ All LinuxKit test VMs cleaned up"
  else
    info "Cleanup cancelled"
  fi
}

cleanup_temporary_files() {
  log "🧹 Cleaning up temporary files..."
  
  local output_dir="output"
  local temp_files=(
    "$output_dir/homebridge-*.vmdk"
    "$output_dir/homebridge-*.img"
    "$output_dir/homebridge-*.raw"
  )
  
  local cleaned=false
  for pattern in "${temp_files[@]}"; do
    for file in $pattern; do
      if [[ -f "$file" && "$file" =~ \.(vmdk|img|raw)$ ]]; then
        # Only remove files that look like converted/temporary files
        if [[ "$file" =~ homebridge-(amd64|arm64)\.(vmdk|img|raw)$ ]]; then
          warn "Removing temporary file: $file"
          rm -f "$file" || true
          cleaned=true
        fi
      fi
    done
  done
  
  if [[ "$cleaned" == "true" ]]; then
    log "✅ Temporary files cleaned up"
  else
    info "No temporary files to clean up"
  fi
}

main() {
  echo "🧹 LinuxKit VM Cleanup"
  echo "======================"
  
  check_dependencies
  
  case "$TARGET" in
    "all")
      cleanup_all_linuxkit_vms
      cleanup_temporary_files
      ;;
    "amd64"|"arm64")
      local vm_name="homebridge-linuxkit-test"
      cleanup_vm "$vm_name"
      cleanup_temporary_files
      ;;
    *)
      error "Invalid target: $TARGET"
      echo "Valid targets: amd64, arm64, all"
      exit 1
      ;;
  esac
  
  log "🎉 Cleanup completed!"
}

main "$@"
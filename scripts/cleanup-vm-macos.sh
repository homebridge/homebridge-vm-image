#!/usr/bin/env bash

# macOS VirtualBox VM Cleanup Script
# This script cleans up VMs and files created by validate-vm-macos.sh
#
# Usage:
#   ./cleanup-vm-macos.sh [architecture]
#   
# Arguments:
#   architecture: 'amd64' or 'arm64' (cleans up both if not specified)
#
# Example:
#   ./cleanup-vm-macos.sh       # Clean up all VMs and files
#   ./cleanup-vm-macos.sh amd64 # Clean up only amd64 files
#   ./cleanup-vm-macos.sh arm64 # Clean up only arm64 files

set -euo pipefail

# Configuration
ARCHITECTURE="${1:-}"
VM_NAME="homebridge-test-vm"
LOG_FILE="cleanup-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# Logging function
log() {
    local message="$1"
    local color="${2:-$NC}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${color}${message}${NC}"
    echo "[$timestamp] $message" >> "$LOG_FILE"
}

# Show help if requested
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" ]]; then
    echo "macOS VirtualBox VM Cleanup Script"
    echo ""
    echo "Usage: $0 [architecture]"
    echo ""
    echo "Arguments:"
    echo "  architecture    'amd64', 'arm64', or omit for both (optional)"
    echo ""
    echo "Examples:"
    echo "  $0              # Clean up all VMs and files"
    echo "  $0 amd64        # Clean up only AMD64 files"
    echo "  $0 arm64        # Clean up only ARM64 files"
    echo ""
    echo "This script removes:"
    echo "  - VirtualBox VMs named '$VM_NAME'"
    echo "  - Downloaded VM image files (*.img.gz, *.img, *.vdi)"
    echo "  - Console log files (vm-console-*.log)"
    echo "  - Validation result files"
    exit 0
fi

log "🧹 Starting VirtualBox VM cleanup..." "$BLUE"

# Clean up VM
if VBoxManage list vms | grep -q "$VM_NAME"; then
    log "🗑️ Cleaning up VM '$VM_NAME'..." "$YELLOW"
    VBoxManage controlvm "$VM_NAME" poweroff 2>/dev/null || true
    sleep 2
    VBoxManage unregistervm "$VM_NAME" --delete 2>/dev/null || true
    log "✅ VM '$VM_NAME' removed" "$GREEN"
else
    log "ℹ️ No VM named '$VM_NAME' found" "$GRAY"
fi

# Clean up files based on architecture
cleanup_files_for_arch() {
    local arch="$1"
    local files_removed=0
    
    log "🗂️ Cleaning up files for $arch architecture..." "$YELLOW"
    
    # VM image files
    for file in "homebridge-${arch}.img.gz" "homebridge-${arch}.img" "homebridge-${arch}.vdi"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log "   Removed: $file" "$GRAY"
            ((files_removed++))
        fi
    done
    
    # Console log file
    if [[ -f "vm-console-${arch}.log" ]]; then
        rm -f "vm-console-${arch}.log"
        log "   Removed: vm-console-${arch}.log" "$GRAY"
        ((files_removed++))
    fi
    
    if [[ $files_removed -eq 0 ]]; then
        log "   No files found for $arch architecture" "$GRAY"
    else
        log "   Removed $files_removed file(s) for $arch" "$GREEN"
    fi
}

# Clean up validation results and screenshots
cleanup_validation_files() {
    local files_removed=0
    
    log "📊 Cleaning up validation files..." "$YELLOW"
    
    # Validation results
    for file in validation-results.json vm-screenshot.png; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log "   Removed: $file" "$GRAY"
            ((files_removed++))
        fi
    done
    
    # Old validation log files (keep current one)
    find . -maxdepth 1 -name "validation-*.log" -not -name "$LOG_FILE" -type f 2>/dev/null | while read -r file; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log "   Removed: $file" "$GRAY"
            ((files_removed++))
        fi
    done 2>/dev/null || true
    
    if [[ $files_removed -eq 0 ]]; then
        log "   No validation files found" "$GRAY"
    else
        log "   Removed $files_removed validation file(s)" "$GREEN"
    fi
}

# Determine which architectures to clean up
if [[ -n "$ARCHITECTURE" ]]; then
    if [[ "$ARCHITECTURE" == "amd64" || "$ARCHITECTURE" == "arm64" ]]; then
        cleanup_files_for_arch "$ARCHITECTURE"
    else
        log "❌ Invalid architecture: $ARCHITECTURE. Use 'amd64' or 'arm64'" "$RED"
        exit 1
    fi
else
    # Clean up both architectures
    cleanup_files_for_arch "amd64"
    cleanup_files_for_arch "arm64"
fi

# Clean up validation files
cleanup_validation_files

log "✨ Cleanup completed successfully!" "$GREEN"
log "📋 Cleanup log: $LOG_FILE" "$GRAY"

# Show what's left (if anything)
remaining_files=()
for pattern in "homebridge-*.img*" "homebridge-*.vdi" "vm-console-*.log" "validation-*.log" "validation-results.json" "vm-screenshot.png"; do
    while IFS= read -r -d '' file; do
        remaining_files+=("$file")
    done < <(find . -maxdepth 1 -name "$pattern" -not -name "$LOG_FILE" -print0 2>/dev/null) || true
done

if [[ ${#remaining_files[@]} -gt 0 ]]; then
    log "📁 Remaining files:" "$BLUE"
    for file in "${remaining_files[@]}"; do
        log "   $file" "$GRAY"
    done
else
    log "🎉 All validation files cleaned up!" "$GREEN"
fi
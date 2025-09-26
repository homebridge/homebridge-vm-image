#!/usr/bin/env bash

# Test script to validate APT updates work correctly and source.sh is preserved
# This should be run inside a running VM

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARN:${NC} $*" >&2; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $*" >&2; }

SOURCE_FILE="/opt/homebridge/source.sh"
VM_MARKER="# Appended by homebridge-vm-image"

test_source_file_exists() {
    log "🔍 Testing if source.sh exists and has VM additions..."
    if [ ! -f "$SOURCE_FILE" ]; then
        error "Source file does not exist: $SOURCE_FILE"
        return 1
    fi
    
    if ! grep -q "$VM_MARKER" "$SOURCE_FILE"; then
        error "VM marker not found in $SOURCE_FILE"
        return 1
    fi
    
    log "✅ Source file exists with VM additions"
}

test_password_system() {
    log "🔍 Testing secure password system..."
    
    # Check that we don't store passwords in plaintext
    if [ -f "/etc/hb-root-password" ]; then
        error "Found insecure plaintext password file (should not exist)"
        return 1
    fi
    
    # Check that the marker file exists (indicating password was set)
    if [ -f "/etc/hb-root-password-set" ]; then
        log "✅ Secure password system marker found"
    else
        warn "Password system marker not found (may not have run first boot yet)"
    fi
}

test_apt_update() {
    log "🔄 Testing APT update..."
    apt-get update -qq
    log "✅ APT update completed"
}

test_homebridge_package_operations() {
    log "🔄 Testing Homebridge package operations..."
    
    # Get current version
    CURRENT_VERSION=$(dpkg -l homebridge | awk '/^ii/ {print $3}')
    log "Current Homebridge version: $CURRENT_VERSION"
    
    # Reinstall to trigger package operations
    log "Reinstalling Homebridge package..."
    apt-get install --reinstall homebridge -y -qq
    
    log "✅ Package operations completed"
}

test_source_file_preserved() {
    log "🔍 Testing if source.sh VM additions are preserved..."
    if [ ! -f "$SOURCE_FILE" ]; then
        error "Source file missing after package operation: $SOURCE_FILE"
        return 1
    fi
    
    if ! grep -q "$VM_MARKER" "$SOURCE_FILE"; then
        error "VM additions lost after package operation"
        return 1
    fi
    
    # Check for VM-specific environment variables
    if ! grep -q "HOMEBRIDGE_VM_IMAGE_VERSION" "$SOURCE_FILE"; then
        error "VM environment variables missing"
        return 1
    fi
    
    log "✅ Source file VM additions preserved"
}

test_protection_scripts() {
    log "🔍 Testing protection scripts..."
    
    if [ ! -f "/usr/local/sbin/protect-vm-config" ]; then
        error "Protection script missing"
        return 1
    fi
    
    if [ ! -f "/etc/apt/apt.conf.d/00-pre-invoke-homebridge-vm" ]; then
        error "APT pre-invoke hook missing"
        return 1
    fi
    
    if [ ! -f "/etc/apt/apt.conf.d/99-post-invoke-homebridge-vm" ]; then
        error "APT post-invoke hook missing"
        return 1
    fi
    
    log "✅ Protection scripts are installed"
}

main() {
    echo "🧪 Testing APT Updates and Configuration Persistence"
    echo "=================================================="
    
    # Ensure we're running as root
    if [ $(id -u) -ne 0 ]; then
        error "This script must be run as root"
        exit 1
    fi
    
    test_source_file_exists
    test_password_system
    test_protection_scripts
    test_apt_update
    test_source_file_preserved
    test_homebridge_package_operations
    test_source_file_preserved
    
    log "🎉 All tests passed! APT updates work correctly and configurations are preserved."
}

main "$@"
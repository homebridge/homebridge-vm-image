#!/bin/bash

# Script to configure and export a UTM Virtual Machine on macOS for Homebridge
# Copies and edits template-utm-config.plist, boots from a user-specified disk image,
# uses bridged networking, supports user-specified or host architecture (defaults to arm64 on Apple Silicon),
# copies homebridge-icon.png, and sets manifest contents (same basename as disk image, preserving newlines) as Information:Notes.
# Prerequisites: UTM installed, utmctl in PATH, template-utm-config.plist in script directory,
# ../assets/homebridge-icon.png, disk image, and corresponding .manifest file.
# Usage: ./configure_and_export_utm_vm.sh <path_to_disk_image> <export_output_path> [arm64|amd64]

# Exit on error
set -e

# Logging functions
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARN:${NC} $*" >&2; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $*" >&2; }
info() { echo -e "${BLUE}[$(date +'%H:%M:%S')] INFO:${NC} $*" >&2; }
group_log() {
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        echo -e "::group::$*"
    else
        log "$*"
    fi
}
group_end() {
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        echo -e "::endgroup::"
    fi
}

# Function to check if utmctl is in PATH
check_utmctl() {
    if ! command -v utmctl &> /dev/null; then
        error "utmctl not found in PATH. Ensure UTM is installed and utmctl is accessible."
        error "Hint: UTM's utmctl is typically at /Applications/UTM.app/Contents/MacOS/utmctl. Add it to PATH or symlink to /usr/local/bin."
        exit 1
    fi
    info "utmctl found in PATH"
}

# Function to check if PlistBuddy is available
check_plistbuddy() {
    if ! command -v /usr/libexec/PlistBuddy &> /dev/null; then
        error "/usr/libexec/PlistBuddy not found. This is a macOS system tool—ensure you're on macOS."
        exit 1
    fi
    info "PlistBuddy found"
}

# Function to check if the disk image exists
check_disk_image() {
    local disk_path="$1"
    if [[ ! -f "$disk_path" ]]; then
        error "Disk image not found at $disk_path"
        exit 1
    fi
    if [[ ! "$disk_path" =~ \.(qcow2|img)$ ]]; then
        error "Disk image must be a .qcow2 or .img file"
        exit 1
    fi
    info "Disk image validated: $disk_path"
}

# Function to check if template-utm-config.plist exists
check_template() {
    local template="template-utm-config.plist"
    if [[ ! -f "$template" ]]; then
        error "template-utm-config.plist not found in script directory."
        exit 1
    fi
    info "Template found: $template"
}

# Function to check if homebridge-icon.png exists
check_icon() {
    local icon_path="../assets/homebridge-icon.png"
    if [[ ! -f "$icon_path" ]]; then
        error "homebridge-icon.png not found at $icon_path"
        exit 1
    fi
    info "Icon found: $icon_path"
}

# Function to check if manifest file exists
check_manifest() {
    local manifest="$1"
    if [[ ! -f "$manifest" ]]; then
        error "Manifest file not found at $manifest"
        exit 1
    fi
    info "Manifest found: $manifest"
}

# Function to check if UTM directory exists
check_utm_dir() {
    local utm_dir="$HOME/UTM"
    if [[ ! -d "$utm_dir" ]]; then
        warn "UTM directory $utm_dir does not exist. Creating it."
        mkdir -p "$utm_dir"
    fi
    info "UTM directory verified: $utm_dir"
}

# Function to generate a random MAC address (locally administered, UTM-compatible)
generate_mac_address() {
    printf "FA:%02X:%02X:%02X:%02X:%02X" $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256))
}

# Function to determine architecture (maps to UTM config values)
get_architecture() {
    local input_arch="$1"
    local host_arch
    host_arch=$(uname -m)
    info "Detected host architecture: $host_arch"

    if [[ -z "$input_arch" ]]; then
        if [[ "$host_arch" == "arm64" ]]; then
            info "Defaulting to aarch64 (host is arm64)"
            echo "aarch64"
        elif [[ "$host_arch" == "x86_64" ]]; then
            info "Defaulting to x86_64 (host is x86_64)"
            echo "x86_64"
        else
            error "Unsupported host architecture: $host_arch"
            exit 1
        fi
    else
        if [[ "$input_arch" == "arm64" ]]; then
            info "User specified arm64 (maps to aarch64)"
            echo "aarch64"
        elif [[ "$input_arch" == "amd64" ]]; then
            if [[ "$host_arch" == "arm64" ]]; then
                warn "Specifying amd64 on an arm64 host may cause issues if the disk image is arm64-based."
            fi
            info "User specified amd64 (maps to x86_64)"
            echo "x86_64"
        else
            error "Architecture must be 'arm64' or 'amd64'"
            exit 1
        fi
    fi
}

# Function to configure the VM
configure_vm() {
    local disk_path="$1"
    local arch="$2"
    local vm_name="Homebridge-VM"
    local vm_dir="$HOME/UTM/$vm_name.utm"
    local plist="$vm_dir/config.plist"
    local template="template-utm-config.plist"
    local icon_path="../assets/homebridge-icon.png"
    local disk_basename
    disk_basename=$(basename "$disk_path" .qcow2 2>/dev/null || basename "$disk_path" .img)
    local manifest="${disk_path%.*}.manifest"
    local cpu_cores=2
    local disk_filename="homebridge-vm-image-$arch.qcow2"
    local uuid
    uuid=$(uuidgen)
    local mac_address
    mac_address=$(generate_mac_address)

    group_log "Starting UTM VM configuration for $vm_name with architecture $arch"
    check_utmctl
    check_plistbuddy
    check_disk_image "$disk_path"
    check_template
    check_icon
    check_manifest "$manifest"
    check_utm_dir

    # Clean up if VM already exists
    if [[ -d "$vm_dir" ]]; then
        info "Removing existing VM directory: $vm_dir"
        rm -rf "$vm_dir"
    fi

    # Create bundle structure
    info "Creating VM directory: $vm_dir/Data"
    mkdir -p "$vm_dir/Data"

    # Copy disk image
    info "Copying disk image to $vm_dir/Data/$disk_filename"
    cp "$disk_path" "$vm_dir/Data/$disk_filename"
    chmod 644 "$vm_dir/Data/$disk_filename"

    # Copy icon
    info "Copying icon to $vm_dir/Data/homebridge-icon.png"
    cp "$icon_path" "$vm_dir/Data/homebridge-icon.png"
    chmod 644 "$vm_dir/Data/homebridge-icon.png"

    # Copy and edit template plist
    info "Copying and editing $template to $plist"
    cp "$template" "$plist"
    chmod 644 "$plist"
    /usr/libexec/PlistBuddy -c "Set :Information:Name $vm_name" "$plist"
    /usr/libexec/PlistBuddy -c "Set :Information:UUID $uuid" "$plist"
    /usr/libexec/PlistBuddy -c "Set :Information:Icon homebridge-icon.png" "$plist"
    /usr/libexec/PlistBuddy -c "Set :Information:IconCustom true" "$plist"
    /usr/libexec/PlistBuddy -c "Set :Drive:0:ImageName $disk_filename" "$plist"
    /usr/libexec/PlistBuddy -c "Set :Drive:0:Identifier $uuid" "$plist"
    /usr/libexec/PlistBuddy -c "Set :Network:0:MacAddress $mac_address" "$plist"
    /usr/libexec/PlistBuddy -c "Set :System:Architecture $arch" "$plist"
    /usr/libexec/PlistBuddy -c "Set :System:CPUCount $cpu_cores" "$plist"

    # Read manifest and set as Information:Notes, preserving newlines
    info "Reading manifest from $manifest"
    local manifest_content
    # Escape quotes and backslashes to make content PlistBuddy-compatible
    manifest_content=$(cat "$manifest" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')
    /usr/libexec/PlistBuddy -c "Delete :Information:Notes" "$plist" 2>/dev/null || true
    # Use a temporary file to handle multiline content
    echo "$manifest_content" > /tmp/manifest_content.txt
    /usr/libexec/PlistBuddy -c "Add :Information:Notes string" "$plist"
    /usr/libexec/PlistBuddy -c "Set :Information:Notes \"$(cat /tmp/manifest_content.txt)\"" "$plist"
    rm -f /tmp/manifest_content.txt

    # Verify architecture in config.plist
    local plist_arch
    plist_arch=$(/usr/libexec/PlistBuddy -c "Print :System:Architecture" "$plist")
    info "Configured VM architecture in config.plist: $plist_arch"
    if [[ "$plist_arch" != "$arch" ]]; then
        error "config.plist architecture ($plist_arch) does not match requested ($arch)"
        exit 1
    fi

    # Register VM with UTM
    info "Registering VM with UTM by opening $vm_dir"
    open -a UTM "$vm_dir" || warn "Failed to open VM in UTM GUI; attempting utmctl start anyway"

    # Start the VM with retry
    info "Starting VM: $vm_name"
    local retries=3
    local delay=5
    for ((i=1; i<=retries; i++)); do
        if utmctl start "$vm_name"; then
            info "VM started successfully"
            break
        fi
        warn "Attempt $i/$retries: Failed to start VM. Retrying after $delay seconds..."
        sleep $delay
        if [[ $i -eq $retries ]]; then
            error "Failed to start VM after $retries attempts. Check ~/Library/Logs/UTM/ for errors or ensure UTM has permissions."
            error "Run 'utmctl list' to verify VM registration. VM directory contents:"
            ls -l "$vm_dir" >&2
            ls -l "$vm_dir/Data" >&2
            utmctl list >&2
            exit 1
        fi
    done

    log "VM configuration completed successfully!"
    log "The VM '$vm_name' is running with bridged networking, architecture $arch, and set to boot from the provided disk image."
    group_end
}

# Function to export the VM
export_vm() {
    local vm_name="Homebridge-VM"
    local output_path="$1"
    local vm_dir="$HOME/UTM/$vm_name.utm"

    group_log "Exporting VM: $vm_name to $output_path"
    # Stop the VM if running
    info "Stopping VM if running..."
    utmctl stop "$vm_name" || true

    # Ensure output directory exists
    info "Creating output directory: $(dirname "$output_path")"
    mkdir -p "$(dirname "$output_path")"

    # Compress the VM bundle
    info "Compressing VM to $output_path"
    zip -r "$output_path" "$vm_dir"

    log "VM exported successfully to $output_path"
    group_end
}

# Check for arguments
if [[ $# -lt 2 ]] || [[ $# -gt 3 ]]; then
    error "Usage: $0 <path_to_disk_image> <export_output_path> [arm64|amd64]"
    exit 1
fi

# Get architecture (user-provided or host default)
group_log "Determining architecture"
architecture=$(get_architecture "$3")
group_end

# Run the configuration and export
configure_vm "$1" "$architecture"
export_vm "$2"

log "Process completed! VM configured with bridged networking, architecture $architecture, set to boot from provided disk image, and exported to $2"
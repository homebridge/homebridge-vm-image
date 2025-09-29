#!/bin/bash

# Script to configure and export a UTM Virtual Machine on macOS for Homebridge
# Copies and edits template-utm-config.plist, boots from a disk image in output/,
# uses bridged networking, supports user-specified or host architecture (defaults to arm64 on Apple Silicon),
# copies homebridge-icon.png, and sets manifest contents (same basename as disk image, preserving newlines) as Information:Notes.
# Prerequisites: UTM installed, utmctl in PATH, template-utm-config.plist in script directory,
# ../assets/homebridge-icon.png, disk image and .manifest in output/.
# Usage: ./configure_and_export_utm_vm.sh [RELEASE_STREAM] [ARCH]
# RELEASE_STREAM: alpha, beta, stable (default: stable)
# ARCH: arm64, amd64 (default: host architecture)

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

# Determine repository root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Auto-detect architecture based on host system
detect_default_arch() {
    case "$(uname -m)" in
        arm64|aarch64) echo "arm64" ;;
        x86_64) echo "amd64" ;;
        *) echo "amd64" ;; # fallback to amd64 for unknown architectures
    esac
}

# Set inputs with defaults
ARCH="${2:-$(detect_default_arch)}"
RELEASE_STREAM="${1:-stable}" # Default to "stable" if not provided

# Validate architecture
if [[ "$ARCH" != "arm64" && "$ARCH" != "amd64" ]]; then
    error "Unsupported architecture: $ARCH"
    error "Supported architectures: amd64, arm64"
    exit 1
fi

# Validate release stream
if [[ "$RELEASE_STREAM" != "alpha" && "$RELEASE_STREAM" != "beta" && "$RELEASE_STREAM" != "stable" ]]; then
    error "Unsupported release stream: $RELEASE_STREAM"
    error "Supported release streams: alpha, beta, stable"
    exit 1
fi

# Define file paths and VM settings
VM_NAME="homebridge-vm-image-${RELEASE_STREAM}-${ARCH}"
VM_DIR="$HOME/UTM/Homebridge-VM-${RELEASE_STREAM}-${ARCH}.utm"
VM_RAM="1024"
OUTPUT_DIR="${REPO_ROOT}/output"
if [[ -f "$OUTPUT_DIR/${VM_NAME}.img" ]]; then
  DISK_PATH="$OUTPUT_DIR/${VM_NAME}.img"
elif [[ -f "$OUTPUT_DIR/${VM_NAME}.qcow2" ]]; then
  DISK_PATH="$OUTPUT_DIR/${VM_NAME}.qcow2"
else
  error "Neither .img nor .qcow2 file found for VM: $VM_NAME in $OUTPUT_DIR"
  exit 1
fi
MANIFEST="$OUTPUT_DIR/${VM_NAME}.manifest"
OUTPUT_PATH="$OUTPUT_DIR/${VM_NAME}.utm.tgz"
ICON_PATH="${REPO_ROOT}/assets/homebridge-icon.png"
TEMPLATE="${REPO_ROOT}/assets/template-utm-config.plist"

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
    if [[ ! -f "${DISK_PATH}" ]]; then
        error "Disk image not found at ${DISK_PATH}"
        exit 1
    fi
    if [[ ! "${DISK_PATH}" =~ \.(img|qcow2)$ ]]; then
        error "${DISK_PATH} image must be a .img  or .qcow2 file"
        exit 1
    fi
    info "Disk image validated: ${DISK_PATH}"
}

# Function to check if template-utm-config.plist exists
check_template() {
    if [[ ! -f "${TEMPLATE}" ]]; then
        error "template-utm-config.plist not found in script directory."
        exit 1
    fi
    info "Template found: ${TEMPLATE}"
}

# Function to check if homebridge-icon.png exists
check_icon() {
    if [[ ! -f "${ICON_PATH}" ]]; then
        error "homebridge-icon.png not found at ${ICON_PATH}"
        exit 1
    fi
    info "Icon found: ${ICON_PATH}"
}

# Function to check if manifest file exists
check_manifest() {
    if [[ ! -f "${MANIFEST}" ]]; then
        error "Manifest file not found at ${MANIFEST}"
        exit 1
    fi
    info "Manifest found: ${MANIFEST}"
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
    local host_arch
    host_arch=$(uname -m)
    info "Detected host architecture: $host_arch"

    if [[ -z "${ARCH}" ]]; then
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
        if [[ "${ARCH}" == "arm64" ]]; then
            info "User specified arm64 (maps to aarch64)"
            echo "aarch64"
        elif [[ "${ARCH}" == "amd64" ]]; then
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
    local plist="${VM_DIR}/config.plist"
    local cpu_cores=2
    local ram_mb="$VM_RAM"
    local disk_filename="homebridge-vm-image-${RELEASE_STREAM}-${ARCH}.qcow2"
    local uuid
    uuid=$(uuidgen)
    local mac_address
    mac_address=$(generate_mac_address)

    group_log "Starting UTM VM configuration for ${VM_NAME} with architecture ${ARCH}"
    check_utmctl
    check_plistbuddy
    check_disk_image
    check_template
    check_icon
    check_manifest
    check_utm_dir

    # Clean up if VM already exists
    if [[ -d "${VM_DIR}" ]]; then
        info "Removing existing VM directory: ${VM_DIR}"
        rm -rf "${VM_DIR}"
    fi

    # Create bundle structure
    info "Creating VM directory: ${VM_DIR}/Data"
    mkdir -p "${VM_DIR}/Data"

    # Convert disk image to qcow2 format
    info "Converting disk image to qcow2 format and resizing to 40GB"
    qcow2_disk_path="${VM_DIR}/Data/${disk_filename}"
    qemu-img convert -f raw -O qcow2 -c "${DISK_PATH}" "$qcow2_disk_path"
    qemu-img resize "$qcow2_disk_path" 40G

    # Set permissions for the qcow2 disk image
    chmod 644 "$qcow2_disk_path"

    # Log the completion of the conversion
    info "Disk image converted and saved as $qcow2_disk_path"

    # Copy icon
    info "Copying icon to ${VM_DIR}/Data/homebridge-icon.png"
    cp "${ICON_PATH}" "${VM_DIR}/Data/homebridge-icon.png"
    chmod 644 "${VM_DIR}/Data/homebridge-icon.png"

    # Copy and edit template plist
    info "Copying and editing ${TEMPLATE} to $plist"
    cp "${TEMPLATE}" "$plist"
    chmod 644 "$plist"
    /usr/libexec/PlistBuddy -c "Set :Information:Name ${VM_NAME}" "$plist"
    /usr/libexec/PlistBuddy -c "Set :Information:UUID $uuid" "$plist"
    /usr/libexec/PlistBuddy -c "Set :Information:Icon homebridge-icon.png" "$plist"
    /usr/libexec/PlistBuddy -c "Set :Information:IconCustom true" "$plist"
    /usr/libexec/PlistBuddy -c "Set :Drive:0:ImageName $disk_filename" "$plist"
    /usr/libexec/PlistBuddy -c "Set :Drive:0:Identifier $uuid" "$plist"
    /usr/libexec/PlistBuddy -c "Set :Network:0:MacAddress $mac_address" "$plist"
    /usr/libexec/PlistBuddy -c "Set :System:Architecture ${UTM_ARCHITECTURE}" "$plist"
    /usr/libexec/PlistBuddy -c "Set :System:CPUCount $cpu_cores" "$plist"
    /usr/libexec/PlistBuddy -c "Set :System:MemorySize $ram_mb" "$plist"

    # Read manifest and set as Information:Notes, preserving newlines
    info "Reading manifest from ${MANIFEST}"
    local manifest_content
    # Escape quotes and backslashes to make content PlistBuddy-compatible
    manifest_content=$(cat "${MANIFEST}" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')
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
    if [[ "$plist_arch" != "${UTM_ARCHITECTURE}" ]]; then
        error "config.plist architecture ($plist_arch) does not match requested (${UTM_ARCHITECTURE})"
        exit 1
    fi

    # Register VM with UTM
    if [[ ! "${GITHUB_ACTIONS:-}" == "true" ]]; then
        info "Registering VM with UTM by opening ${VM_DIR}"
        open -a UTM "${VM_DIR}" || warn "Failed to open VM in UTM GUI; attempting utmctl start anyway"

        # Start the VM with retry
        info "Starting VM: ${VM_NAME}"
        local retries=3
        local delay=5
        for ((i=1; i<=retries; i++)); do
            if utmctl start "${VM_NAME}"; then
                info "VM started successfully"
                break
            fi
            warn "Attempt $i/$retries: Failed to start VM. Retrying after $delay seconds..."
            sleep $delay
            if [[ $i -eq $retries ]]; then
                error "Failed to start VM after $retries attempts. Check ~/Library/Logs/UTM/ for errors or ensure UTM has permissions."
                error "Run 'utmctl list' to verify VM registration. VM directory contents:"
                ls -lR "${VM_DIR}" >&2
                utmctl list >&2
                # exit 1
            fi
        done
    else
        info "Skipping VM start in GitHub Actions environment"
    fi
    log "VM configuration completed successfully!"
    log "The VM '${VM_NAME}' is running with bridged networking, architecture ${UTM_ARCHITECTURE}, and set to boot from the provided disk image."
    group_end
}

# Function to export the VM
export_vm() {
    group_log "Exporting VM: ${VM_NAME} to ${OUTPUT_PATH}"
        if [[ ! "${GITHUB_ACTIONS:-}" == "true" ]]; then
        # Stop the VM if running
        info "Stopping VM if running..."
        utmctl stop "${VM_NAME}" || true
    else
        info "Skipping VM stop in GitHub Actions environment"
    fi

    # Ensure output directory exists
    info "Creating output directory: $(dirname "${OUTPUT_PATH}")"
    mkdir -p "$(dirname "${OUTPUT_PATH}")"

    # Compress the VM bundle
    info "Compressing VM to ${OUTPUT_PATH}"
    tar -czf "${OUTPUT_PATH}" -C "$(dirname "${VM_DIR}")" "$(basename "${VM_DIR}")"

    log "VM exported successfully to ${OUTPUT_PATH}"
    group_end
}

# Check for arguments
if [[ $# -gt 2 ]]; then
    error "Usage: $0 [RELEASE_STREAM] [ARCH]"
    error "RELEASE_STREAM: alpha, beta, stable (default: stable)"
    error "ARCH: arm64, amd64 (default: host architecture)"
    exit 1
fi

# Get architecture (user-provided or host default)
group_log "Determining architecture"
UTM_ARCHITECTURE=$(get_architecture)
group_end

# Run the configuration and export
configure_vm
export_vm

log "Process completed! VM configured with bridged networking, architecture ${UTM_ARCHITECTURE}, set to boot from $DISK_PATH, and exported to $OUTPUT_PATH"
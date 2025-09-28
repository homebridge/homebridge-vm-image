#!/usr/bin/env bash

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DISTRO="bookworm"
readonly SIZE_MB=3072
readonly ESP_SIZE_MB=256

# Debug settings - set DEBUG=1 for verbose output
readonly DEBUG="${DEBUG:-0}"
readonly APT_QUIET=$([[ $DEBUG -eq 1 ]] && echo "" || echo "-qq")
readonly APT_REDIRECT=$([[ $DEBUG -eq 1 ]] && echo "" || echo "> /dev/null 2>&1")
readonly BASH_DEBUG_FLAG=$([[ $DEBUG -eq 1 ]] && echo "x" || echo "")

set -euo pipefail
[[ $DEBUG -eq 1 ]] && set -x

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging functions
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

# Cleanup function
cleanup() {
    local exit_code=$?
    [[ $exit_code -ne 0 ]] && error "Build failed with exit code $exit_code"
    
    if [[ -n "${LOOP_DEV:-}" ]]; then
        info "Cleaning up loop device: $LOOP_DEV"
        
        # Kill any processes using the mountpoints
        sudo fuser -km "${ROOTFS:-}/"{dev,proc,sys} 2>/dev/null || true
        
        # Force unmount everything
        if [[ -n "${ROOTFS:-}" ]]; then
            sudo umount -f "${ROOTFS}/boot/efi" 2>/dev/null || true
            sudo umount -f "${ROOTFS}/proc" 2>/dev/null || true  
            sudo umount -f "${ROOTFS}/sys" 2>/dev/null || true
            sudo umount -f "${ROOTFS}/dev/pts" 2>/dev/null || true
            sudo umount -f "${ROOTFS}/dev" 2>/dev/null || true
            sudo umount -f "${ROOTFS}" 2>/dev/null || true
        fi
        
        [[ -n "${ESP_MOUNTDIR:-}" ]] && sudo umount -f "${ESP_MOUNTDIR}" 2>/dev/null || true
        
        # Remove partition mappings
        sudo kpartx -d "$LOOP_DEV" 2>/dev/null || true
        
        # Detach loop device  
        sudo losetup -d "$LOOP_DEV" 2>/dev/null || true
        
        info "Cleanup completed"
    fi
    
    [[ $exit_code -eq 0 ]] && log "✅ Build completed successfully"
    exit $exit_code
}

trap cleanup EXIT INT TERM

# Validate architecture
validate_arch() {
    local arch="$1"
    case "${ARCH}" in
        arm64|amd64) return 0 ;;
        *) error "Unsupported architecture: ${ARCH}" && exit 1 ;;
    esac
}

# Wait for device to appear
wait_for_device() {
    local device="$1"
    local timeout=10
    local count=0
    
    info "Waiting for device: $device"
    while [[ ! -b "$device" && $count -lt $timeout ]]; do
        sleep 1
        ((count++))
        [[ $DEBUG -eq 1 ]] && info "Waiting... ($count/$timeout)"
    done
    
    if [[ ! -b "$device" ]]; then
        error "Device $device not found after ${timeout}s"
        info "Available devices:"
        ls -la /dev/mapper/ || true
        ls -la /dev/loop* || true
        sudo kpartx -l "${LOOP_DEV}" || true
        return 1
    fi
    info "Device ready: $device"
}

# Create and partition disk image
create_image() {
    local img_path="$1"
    local size_mb="$2"
    
    info "Creating ${size_mb}MB disk image: $img_path"
    
    # Use fallocate for faster allocation
    fallocate -l "${size_mb}M" "$img_path" || dd if=/dev/zero of="$img_path" bs=1M count="$size_mb"
    
    # Create partitions
    parted -s "$img_path" -- \
        mklabel gpt \
        mkpart ESP fat32 1MiB "${ESP_SIZE_MB}MiB" \
        set 1 esp on \
        mkpart primary ext4 "${ESP_SIZE_MB}MiB" 100%
}

# Setup loop device and format partitions
setup_loop_device() {
    local img_path="$1"
    
    info "Setting up loop device for $img_path"
    LOOP_DEV=$(sudo losetup --find --show "$img_path")
    info "Loop device created: $LOOP_DEV"
    
    info "Adding partition mappings"
    sudo kpartx -av "$LOOP_DEV"
    
    # Give udev time to create device nodes
    sleep 2
    sudo udevadm settle
    
    local base_name=$(basename "$LOOP_DEV")
    ESP_PART="/dev/mapper/${base_name}p1"
    ROOT_PART="/dev/mapper/${base_name}p2"
    
    info "Expected partitions: $ESP_PART, $ROOT_PART"
    
    # Wait for devices
    wait_for_device "$ESP_PART" || return 1
    wait_for_device "$ROOT_PART" || return 1
    
    info "Formatting ESP partition: $ESP_PART"
    sudo mkfs.vfat -F32 "$ESP_PART" >/dev/null
    
    info "Formatting root partition: $ROOT_PART"
    sudo mkfs.ext4 -q "$ROOT_PART"
    
    # Get UUIDs
    info "Getting partition UUIDs"
    ESP_UUID=$(sudo blkid -s UUID -o value "$ESP_PART")
    ROOT_UUID=$(sudo blkid -s UUID -o value "$ROOT_PART")
    info "ESP UUID: $ESP_UUID, Root UUID: $ROOT_UUID"
}

# Bootstrap or restore cached rootfs
setup_rootfs() {
    local arch="$1"
    local cache_file="${CACHE_DIR}/debootstrap-${DISTRO}-${ARCH}.tar.gz"
    
    sudo mount "$ROOT_PART" "$ROOTFS"
    
    if [[ -f "$cache_file" ]]; then
        log "Restoring cached rootfs ($(du -sh "$cache_file" | cut -f1))"
        sudo tar -xzf "$cache_file" -C "$ROOTFS"
    else
        log "Running debootstrap for ${ARCH}"
        
        # Install zstd on host if available for faster debootstrap
        if command -v apt-get >/dev/null 2>&1 && ! command -v zstd >/dev/null 2>&1; then
            info "Installing zstd for faster debootstrap"
            sudo apt-get update -qq ${APT_REDIRECT} || true
            sudo apt-get install -y -qq zstd ${APT_REDIRECT} || true
        fi
        
        sudo debootstrap --arch="${ARCH}" --variant=minbase "$DISTRO" "$ROOTFS" \
            http://deb.debian.org/debian
        
        if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
            info "Skipping cache save on GitHub Actions runner"
        else
            info "Caching debootstrap result ($(du -sh "$ROOTFS" | cut -f1))"
            sudo tar -czf "$cache_file" -C "$ROOTFS" .
        fi
    fi
}

# Mount everything for chroot
mount_for_chroot() {
    info "Mounting filesystems for chroot"
    
    # Bind mount system directories
    for dir in dev sys proc; do
        sudo mount --bind "/$dir" "${ROOTFS}/$dir"
    done
    
    sudo mkdir -p "${ROOTFS}/dev/pts"
    sudo mount --bind /dev/pts "${ROOTFS}/dev/pts"
    
    # Mount ESP
    sudo mount "$ESP_PART" "$ESP_MOUNTDIR"
    sudo mkdir -p "${ROOTFS}/boot/efi"
    sudo mount --bind "$ESP_MOUNTDIR" "${ROOTFS}/boot/efi"
}

# Configure base system in chroot
configure_base_system() {
    local arch="$1"
    
    group_log "Configuring base system"
    
    # Copy GRUB modules for amd64 compatibility
    if [[ "${ARCH}" == "amd64" && -d "/usr/lib/grub/x86_64-efi" ]]; then
        sudo mkdir -p "${ROOTFS}/usr/lib/grub/amd64-efi"
        sudo cp -r /usr/lib/grub/x86_64-efi/* "${ROOTFS}/usr/lib/grub/amd64-efi/"
    fi
    
    # Create chroot script
    cat > /tmp/chroot_setup.sh <<'CHROOT_EOF'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export ARCH="$1"
export ROOT_UUID="$2" 
export ESP_UUID="$3"
export DEBUG="$4"
readonly APT_QUIET=$([[ $DEBUG -eq 1 ]] && echo "" || echo "-qq")
readonly BASH_DEBUG_FLAG=$([[ $DEBUG -eq 1 ]] && echo "x" || echo "")

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

# Configure APT for faster downloads
echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/99nolang
echo 'APT::Install-Recommends "false";' > /etc/apt/apt.conf.d/99norecommends

# Update package lists
apt-get update

log "Installing base system packages"
# Install essential packages first
if [[ $DEBUG -eq 1 ]]; then
  apt-get install -y $APT_QUIET \
  apt-utils locales systemd systemd-sysv
else
  apt-get install -y $APT_QUIET \
  apt-utils locales systemd systemd-sysv > /dev/null 2>&1
fi

LANG=en_GB.UTF-8

sed -i "s/# *\(${LANG} UTF-8\)/\1/" /etc/locale.gen
# Configure locale early
locale-gen
update-locale LANG=${LANG}

log "Installing kernel, bootloader, and utilities"
# Define package lists
KERNEL_PACKAGES=(
  linux-image-${ARCH}
  linux-headers-${ARCH}
  grub-efi-${ARCH}
  grub-efi-${ARCH}-bin
  grub-common
  grub2-common
)

SYSTEM_UTILITIES=(
  wget
  psmisc
  procps
  iputils-ping
  logrotate
  openssl
  sudo
  nano
  net-tools
  libnss-mdns
  dbus
  gnupg
  iproute2
  dhcpcd5
  ssh
  zstd
  avahi-daemon
  vim
  dialog
  file
  whiptail
)

VIRTUALIZATION_SUPPORT=(
  hyperv-daemons
)

# Install packages
if [[ $DEBUG -eq 1 ]]; then
  apt-get install -y $APT_QUIET "${KERNEL_PACKAGES[@]}"
  apt-get install -y $APT_QUIET "${SYSTEM_UTILITIES[@]}"
  apt-get install -y $APT_QUIET "${VIRTUALIZATION_SUPPORT[@]}" || true
else
  apt-get install -y $APT_QUIET "${KERNEL_PACKAGES[@]}" > /dev/null 2>&1
  apt-get install -y $APT_QUIET "${SYSTEM_UTILITIES[@]}" > /dev/null 2>&1
  apt-get install -y $APT_QUIET "${VIRTUALIZATION_SUPPORT[@]}" > /dev/null 2>&1 || true
fi

log "Setting up GRUB bootloader"
# Configure GRUB
grub-install \
    --target=${ARCH}-efi \
    --efi-directory=/boot/efi \
    --boot-directory=/boot \
    --bootloader-id=debian \
    --no-nvram \
    --removable \
    --recheck

# GRUB configuration with serial console
cat > /etc/default/grub <<GRUB_EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Homebridge VM on ${ARCH}"
GRUB_CMDLINE_LINUX_DEFAULT="console=tty0 console=ttyS0 root=UUID=$ROOT_UUID"
GRUB_CMDLINE_LINUX="console=tty0 console=ttyS0 root=UUID=$ROOT_UUID"
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --speed=921600 --unit=0 --word=8 --parity=no --stop=1"
GRUB_EOF

update-grub

log "Configuring fstab"
# Create fstab
cat > /etc/fstab <<FSTAB_EOF
UUID=$ROOT_UUID / ext4 defaults,noatime 0 1
UUID=$ESP_UUID /boot/efi vfat umask=0077 0 1
FSTAB_EOF

log "Updating initramfs"
# Configure initramfs
echo "RESUME=none" > /etc/initramfs-tools/conf.d/resume
update-initramfs -c -k all

# Create fallback EFI bootloader
mkdir -p /boot/efi/EFI/BOOT
BOOT_FILE=$(find /boot/efi/EFI -name "grub*.efi" ! -path "*/BOOT/*" | head -1)
if [[ -n "$BOOT_FILE" ]]; then
    case "$BOOT_FILE" in
        *x64*) cp "$BOOT_FILE" /boot/efi/EFI/BOOT/BOOTX64.EFI ;;
        *aa64*) cp "$BOOT_FILE" /boot/efi/EFI/BOOT/BOOTAA64.EFI ;;
    esac
fi

# System configuration
echo "homebridge-vm" > /etc/hostname
cat > /etc/hosts <<HOSTS_EOF
127.0.0.1 localhost
127.0.1.1 homebridge-vm
::1       localhost ip6-localhost ip6-loopback
HOSTS_EOF

# Set root password
echo "root:root" | chpasswd

# Clean package cache
apt-get clean
rm -rf /var/lib/apt/lists/*
CHROOT_EOF

    # Execute chroot script

    sudo chroot "$ROOTFS" /bin/bash -eu${BASH_DEBUG_FLAG} /dev/stdin "${ARCH}" "$ROOT_UUID" "$ESP_UUID" "$DEBUG" < /tmp/chroot_setup.sh
    rm -f /tmp/chroot_setup.sh
    group_end
}

# Install staged assets with better error handling
install_staged_assets() {
    local stage_name="$1"
    local assets_dir="assets/$stage_name"
    
    [[ ! -d "$assets_dir" ]] && { warn "Assets directory not found: $assets_dir"; return 0; }
    
    log "Installing staged assets: $stage_name"
    
    # Install packages
    if [[ -f "$assets_dir/00-packages" ]]; then
        local packages
        packages=$(grep -v '^#' "$assets_dir/00-packages" | tr '\n' ' ' | xargs)
        if [[ -n "$packages" ]]; then
            info "Installing packages: $packages"
            sudo chroot "$ROOTFS" /bin/bash -euc${BASH_DEBUG_FLAG} "
                export DEBIAN_FRONTEND=noninteractive
                apt-get update ${APT_REDIRECT}
                apt-get install -y $APT_QUIET $packages ${APT_REDIRECT}
                apt-get clean
            "
        fi
    fi
    
    # Copy files
#    if [[ -d "$assets_dir/files" ]]; then
#        info "Copying asset files"
#        sudo cp -r "$assets_dir/files/." "$ROOTFS/"
#    fi
    
    # Run scripts
    for script in "$assets_dir"/[0-9][0-9]-run.sh; do
        [[ ! -f "$script" ]] && continue
        
        info "Running script: $(basename "$script")"
        (
            cd "$assets_dir"
            sudo bash -euo pipefail -euc "
                export ROOTFS_DIR='$SCRIPT_DIR/$ROOTFS'
                export DEBIAN_FRONTEND=noninteractive
                export FIRST_USER_NAME='${FIRST_USER_NAME:-homebridge}'
                export BUILD_VERSION='${BUILD_VERSION:-development}'
                export HOMEBRIDGE_APT_PKG_VERSION='${HOMEBRIDGE_APT_PKG_VERSION:-}'
                export FFMPEG_FOR_HOMEBRIDGE_VERSION='${FFMPEG_FOR_HOMEBRIDGE_VERSION:-}'
                export RELEASE_STREAM='${RELEASE_STREAM:-stable}'
                
                on_chroot() {
                    chroot '$SCRIPT_DIR/$ROOTFS' /bin/bash -euo${BASH_DEBUG_FLAG} pipefail \"\$@\"
                }
                export -f on_chroot
                
                source './$(basename "$script")'
            "
        )
    done
}

# Main function
main() {
    local ARCH="${1:-}"
    [[ -z "${ARCH}" ]] && { error "Usage: $0 <architecture> [arm64|amd64]"; exit 1; }
    local RELEASE_STREAM="${2:-stable}"

    if [[ "${RELEASE_STREAM}" != "stable" && "${RELEASE_STREAM}" != "beta" && "${RELEASE_STREAM}" != "alpha" ]] then
        error "Invalid release stream: ${RELEASE_STREAM}. Must be 'stable', 'beta' or 'alpha'."
        exit 1
    fi

    validate_arch "${ARCH}"
    
    # Setup directories and variables
    readonly IMG_NAME="homebridge-vm-image-${RELEASE_STREAM}-${ARCH}" 
    readonly WORKDIR="work-${ARCH}"
    readonly ROOTFS="${WORKDIR}/rootfs"
    readonly MOUNTDIR="${WORKDIR}/mnt"  
    readonly ESP_MOUNTDIR="${WORKDIR}/esp"
    readonly OUTPUT_DIR="output"
    readonly CACHE_DIR="cache"
    readonly IMG_PATH="${OUTPUT_DIR}/${IMG_NAME}.img"
    
    log "Starting Homebridge VM build for release stream ${BLUE}${RELEASE_STREAM}${NC} on arch: ${BLUE}${ARCH}${NC}"
    log "Output: $IMG_PATH"
    log "Debug mode: $([[ $DEBUG -eq 1 ]] && echo "ON" || echo "OFF")"
    
    # Cleanup and create directories
    sudo rm -rf "$WORKDIR" "$OUTPUT_DIR"/*
    mkdir -p "$ROOTFS" "$MOUNTDIR" "$ESP_MOUNTDIR" "$OUTPUT_DIR" "$CACHE_DIR"
    
    # Build process
    group_log "Creating and partitioning disk image"
    create_image "$IMG_PATH" "$SIZE_MB"
    setup_loop_device "$IMG_PATH" 
    setup_rootfs "${ARCH}"
    mount_for_chroot
    group_end

    configure_base_system "${ARCH}"
    
    group_log "Installing Homebridge VM customizations"
    # Install customizations, these are copied from homebridge-raspbian-image
    export FIRST_USER_NAME="homebridge"
    export BUILD_VERSION="${BUILD_VERSION:-$(date +%Y%m%d)-${RELEASE_STREAM}-${ARCH}}"

    export HOMEBRIDGE_APT_PKG_NPM_VERSION=$(jq -r '.dependencies["@homebridge/homebridge-apt-pkg"]' ${RELEASE_STREAM}/package.json | sed 's/\^//')
    export HOMEBRIDGE_APT_PKG_VERSION=$( echo ${HOMEBRIDGE_APT_PKG_NPM_VERSION} | sed 's/-/~/' )
    export FFMPEG_FOR_HOMEBRIDGE_VERSION=v$(jq -r '.dependencies["ffmpeg-for-homebridge"]' ${RELEASE_STREAM}/package.json | sed 's/\^//')

    log "Using homebridge-apt-pkg NPM version: ${BLUE}${HOMEBRIDGE_APT_PKG_NPM_VERSION}${NC}"
    log "Using homebridge-apt-pkg version: ${BLUE}${HOMEBRIDGE_APT_PKG_VERSION}${NC}"
    log "Using ffmpeg-for-homebridge version: ${BLUE}${FFMPEG_FOR_HOMEBRIDGE_VERSION}${NC}"
    
    for stage in $(find assets -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort); do
      group_log "Stage: $stage"
      install_staged_assets "$stage"
      group_end
    done   
    group_end
    local APT_MANIFEST_FILE
    APT_MANIFEST_FILE=$(ls "${ROOTFS}/opt/homebridge/homebridge_apt_pkg"*.manifest 2>/dev/null | head -n 1)
    local APT_MANIFEST=""
    if [[ -f "$APT_MANIFEST_FILE" ]]; then
        # Preserve all lines from the manifest file except header lines, keeping original line returns
        # Keep only lines starting and ending with |, excluding those containing Package or ------
        APT_MANIFEST=$(awk '/^\|.*\|$/ && !/Package/ && !/------/' "$APT_MANIFEST_FILE" | sed 's/\r$//')
    else
        warn "Manifest file not found: ${ROOTFS}/opt/homebridge/homebridge_apt_pkg*.manifest"
    fi

    local MANIFEST_FILE="$OUTPUT_DIR/${IMG_NAME}.manifest"

    {
        echo "Homebridge VM Package Manifest"
        echo
        echo "Release Version: ${BUILD_VERSION}"
        echo
        echo "| Package | Version |"
        echo "|:-------:|:-------:|"
        echo "| Debian | ${DISTRO} |"
        [[ -n "$APT_MANIFEST" ]] && printf "%s\n" "$APT_MANIFEST"
        echo "| ffmpeg for homebridge | ${FFMPEG_FOR_HOMEBRIDGE_VERSION} |"
        echo "| Homebridge APT Package | ${HOMEBRIDGE_APT_PKG_NPM_VERSION} |"
    } > ${MANIFEST_FILE}

    sudo cp ${MANIFEST_FILE} "${ROOTFS}/opt/homebridge/"

    # filepath: [build.sh](http://_vscodecontentref_/0)
    echo "# Appended by homebridge-vm-image" | sudo tee -a "${ROOTFS}/opt/homebridge/source.sh" > /dev/null
    echo "export HOMEBRIDGE_VM_IMAGE_VERSION=${BUILD_VERSION}" | sudo tee -a "${ROOTFS}/opt/homebridge/source.sh" > /dev/null
    echo "export FFMPEG_FOR_HOMEBRIDGE_VERSION=${FFMPEG_FOR_HOMEBRIDGE_VERSION}" | sudo tee -a "${ROOTFS}/opt/homebridge/source.sh" > /dev/null
    echo "export HOMEBRIDGE_APT_PKG_VERSION=${HOMEBRIDGE_APT_PKG_VERSION}" | sudo tee -a "${ROOTFS}/opt/homebridge/source.sh" > /dev/null

    log ""
    log "==> Build completed: $IMG_PATH ($(du -sh "$IMG_PATH" | cut -f1))"

    log ""
    while IFS= read -r line; do
        info "$line"
    done < ${MANIFEST_FILE}
    log ""
}

# Run main function
main "$@"
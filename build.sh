#!/usr/bin/env bash

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DISTRO="bookworm"
readonly SIZE_MB=3072
readonly ESP_SIZE_MB=256

# Debug settings - set DEBUG=1 for verbose output
readonly DEBUG="${DEBUG:-0}"
readonly APT_QUIET=$([[ $DEBUG -eq 1 ]] && echo "" || echo "-qq")
readonly APT_REDIRECT=$([[ $DEBUG -eq 1 ]] && echo "" || echo ">/dev/null 2>&1")
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
    case "$arch" in
        arm64|amd64) return 0 ;;
        *) error "Unsupported architecture: $arch" && exit 1 ;;
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
    local cache_file="${CACHE_DIR}/debootstrap-${DISTRO}-${arch}.tar.gz"
    
    sudo mount "$ROOT_PART" "$ROOTFS"
    
    if [[ -f "$cache_file" ]]; then
        log "Restoring cached rootfs ($(du -sh "$cache_file" | cut -f1))"
        sudo tar -xzf "$cache_file" -C "$ROOTFS"
    else
        log "Running debootstrap for $arch"
        
        # Install zstd on host if available for faster debootstrap
        if command -v apt-get >/dev/null 2>&1 && ! command -v zstd >/dev/null 2>&1; then
            info "Installing zstd for faster debootstrap"
            sudo apt-get update -qq >/dev/null 2>&1 || true
            sudo apt-get install -y -qq zstd >/dev/null 2>&1 || true
        fi
        
        sudo debootstrap --arch="$arch" --variant=minbase "$DISTRO" "$ROOTFS" \
            http://deb.debian.org/debian
        
        info "Caching debootstrap result"
        sudo tar -czf "$cache_file" -C "$ROOTFS" .
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
    
    log "Configuring base system"
    
    # Copy GRUB modules for amd64 compatibility
    if [[ "$arch" == "amd64" && -d "/usr/lib/grub/x86_64-efi" ]]; then
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
export APT_QUIET="$4"

# Configure APT for faster downloads
echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/99nolang
echo 'APT::Install-Recommends "false";' > /etc/apt/apt.conf.d/99norecommends

# Update package lists
apt-get update

# Install essential packages first
apt-get install -y $APT_QUIET \
    apt-utils locales systemd systemd-sysv

# Configure locale early
locale-gen en_CA.UTF-8
echo 'LANG=en_CA.UTF-8' > /etc/default/locale

# Install kernel and bootloader
apt-get install -y $APT_QUIET \
    linux-image-$ARCH linux-headers-$ARCH \
    grub-efi-$ARCH grub-efi-$ARCH-bin grub-common grub2-common

    # Install system utilities
apt-get install -y $APT_QUIET \
    wget psmisc procps iputils-ping logrotate openssl sudo nano \
    net-tools libnss-mdns dbus gnupg iproute2 dhcpcd5 ssh zstd \
    avahi-daemon

# Install virtualization support
apt-get install -y $APT_QUIET hyperv-daemons || true

# Configure GRUB
grub-install \
    --target=${ARCH}-efi \
    --efi-directory=/boot/efi \
    --boot-directory=/boot \
    --bootloader-id=debian \
    --no-nvram \
    --removable \
    --recheck

# GRUB configuration
cat > /etc/default/grub <<GRUB_EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=2
GRUB_DISTRIBUTOR="Homebridge VM - $arch"
GRUB_CMDLINE_LINUX_DEFAULT="console=tty0 console=ttyS0 root=UUID=$ROOT_UUID"
GRUB_CMDLINE_LINUX=""
GRUB_EOF

update-grub

# Create fstab
cat > /etc/fstab <<FSTAB_EOF
UUID=$ROOT_UUID / ext4 defaults,noatime 0 1
UUID=$ESP_UUID /boot/efi vfat umask=0077 0 1
FSTAB_EOF

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
    sudo chroot "$ROOTFS" /bin/bash /dev/stdin "$arch" "$ROOT_UUID" "$ESP_UUID" "$APT_QUIET" < /tmp/chroot_setup.sh
    rm -f /tmp/chroot_setup.sh
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
            sudo chroot "$ROOTFS" /bin/bash -c "
                export DEBIAN_FRONTEND=noninteractive
                apt-get update $APT_REDIRECT
                apt-get install -y $APT_QUIET $packages $APT_REDIRECT
                apt-get clean
            "
        fi
    fi
    
    # Copy files
    if [[ -d "$assets_dir/files" ]]; then
        info "Copying asset files"
        sudo cp -r "$assets_dir/files/." "$ROOTFS/"
    fi
    
    # Run scripts
    for script in "$assets_dir"/[0-9][0-9]-run.sh; do
        [[ ! -f "$script" ]] && continue
        
        info "Running script: $(basename "$script")"
        (
            cd "$assets_dir"
            sudo bash -euo pipefail -c "
                export ROOTFS_DIR='$SCRIPT_DIR/$ROOTFS'
                export DEBIAN_FRONTEND=noninteractive
                export FIRST_USER_NAME='${FIRST_USER_NAME:-homebridge}'
                export BUILD_VERSION='${BUILD_VERSION:-development}'
                
                on_chroot() {
                    chroot '$SCRIPT_DIR/$ROOTFS' /bin/bash -euo pipefail \"\$@\"
                }
                export -f on_chroot
                
                source './$(basename "$script")'
            "
        )
    done
}

# Main function
main() {
    local arch="${1:-}"
    [[ -z "$arch" ]] && { error "Usage: $0 <architecture> [arm64|amd64]"; exit 1; }
    
    validate_arch "$arch"
    
    # Setup directories and variables
    readonly IMG_NAME="homebridge-${arch}.img"
    readonly WORKDIR="work-${arch}"
    readonly ROOTFS="${WORKDIR}/rootfs"
    readonly MOUNTDIR="${WORKDIR}/mnt"  
    readonly ESP_MOUNTDIR="${WORKDIR}/esp"
    readonly OUTPUT_DIR="output"
    readonly CACHE_DIR="cache"
    readonly IMG_PATH="$OUTPUT_DIR/$IMG_NAME"
    
    log "Starting Homebridge VM build for $arch"
    log "Output: $IMG_PATH"
    log "Debug mode: $([[ $DEBUG -eq 1 ]] && echo "ON" || echo "OFF")"
    
    # Cleanup and create directories
    sudo rm -rf "$WORKDIR" "$OUTPUT_DIR"/*
    mkdir -p "$ROOTFS" "$MOUNTDIR" "$ESP_MOUNTDIR" "$OUTPUT_DIR" "$CACHE_DIR"
    
    # Build process
    create_image "$IMG_PATH" "$SIZE_MB"
    setup_loop_device "$IMG_PATH" 
    setup_rootfs "$arch"
    mount_for_chroot
    configure_base_system "$arch"
    
    # Install customizations, these are copied from homebridge-raspbian-image
    export FIRST_USER_NAME="homebridge"
    export BUILD_VERSION="${BUILD_VERSION:-$(date +%Y%m%d)}"
    
    for stage in $(find assets -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort); do
      install_staged_assets "$stage"
    done
    
    log "Build completed: $IMG_PATH ($(du -sh "$IMG_PATH" | cut -f1))"
}

# Run main function
main "$@"
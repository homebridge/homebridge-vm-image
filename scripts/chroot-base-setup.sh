#!/usr/bin/env bash
# Sets up the base system. build-debian-image.sh runs this file INSIDE the new system (chroot),
# as root, right after debootstrap. Never run it on a machine you want to keep.
#
# Arguments: <arch: arm64|amd64> <UUID of the root partition> <UUID of the EFI partition> <debug: 0|1>
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

# The Debian package sources: the release itself, its updates and its security fixes.
# debootstrap leaves only the first one, and that one is frozen between point releases, so a
# system without the other two never gets a security fix.
DISTRO="$(. /etc/os-release && echo "$VERSION_CODENAME")"
rm -f /etc/apt/sources.list
cat > /etc/apt/sources.list.d/debian.sources <<SOURCES_EOF
Types: deb
URIs: https://deb.debian.org/debian
Suites: ${DISTRO} ${DISTRO}-updates
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp

Types: deb
URIs: https://deb.debian.org/debian-security
Suites: ${DISTRO}-security
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp
SOURCES_EOF

# Update package lists, and bring the base system up to date with the security fixes
apt-get update
apt-get -y dist-upgrade

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
  # keeps the clock right. A VM's clock stops while the host computer sleeps, and Debian only
  # "recommends" this package, so it must be named here.
  systemd-timesyncd
  gnupg
  iproute2
  dhcpcd
  ssh
  zstd
  avahi-daemon
  vim.tiny
  dialog
  file
  whiptail
  kbd
)

VIRTUALIZATION_SUPPORT=(
  hyperv-daemons
  spice-vdagent
  qemu-guest-agent
  cloud-guest-utils
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

# GRUB configuration with serial console and resolution
cat > /etc/default/grub <<GRUB_EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR="Homebridge VM on ${ARCH}"
GRUB_CMDLINE_LINUX_DEFAULT="console=tty0 console=ttyS0 root=UUID=$ROOT_UUID"
GRUB_CMDLINE_LINUX="console=tty0 console=ttyS0 root=UUID=$ROOT_UUID"
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --speed=921600 --unit=0 --word=8 --parity=no --stop=1"
GRUB_GFXMODE=1024x768
GRUB_GFXPAYLOAD_LINUX=keep
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
# echo "root:root" | chpasswd

# Clean package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

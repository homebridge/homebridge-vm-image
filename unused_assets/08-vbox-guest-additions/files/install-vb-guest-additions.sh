#!/bin/bash
set -e

readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging functions
log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARN:${NC} $*" >&2; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $*" >&2; }
info() { echo -e "${BLUE}[$(date +'%H:%M:%S')] INFO:${NC} $*" >&2; }

# Check if VirtualBox modules are loaded
if ! dmesg | grep -iq virtualbox; then
  warn "This is not a Virtual Box Host, skipping Guest Additions installation."
  systemctl disable install-vb-guest-additions
  exit 0
fi

log "Installing VirtualBox Guest Additions..."

# Check if the CD-ROM is present
if [[ ! -e /dev/cdrom ]]; then
  error "CD-ROM device not found. Ensure the VirtualBox Guest Additions ISO is attached."
  exit 1
fi

# Install required packages
apt-get update
apt-get install -y build-essential dkms linux-headers-$(uname -r)

# Mount the Guest Additions ISO
mkdir -p /mnt/cdrom
mount /dev/cdrom /mnt/cdrom

# Detect system architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "aarch64" ]]; then
  INSTALLER="/mnt/cdrom/VBoxLinuxAdditions-arm64.run"
elif [[ "$ARCH" == "x86_64" ]]; then
  INSTALLER="/mnt/cdrom/VBoxLinuxAdditions.run"
else
  error "Unsupported architecture: $ARCH"
  umount /mnt/cdrom
  rmdir /mnt/cdrom
  exit 1
fi

# Check if the appropriate installer exists
if [[ -f "$INSTALLER" ]]; then
  log "Running the Guest Additions installer for architecture: $ARCH"
  "$INSTALLER" || true
else
  error "Guest Additions installer not found for architecture: $ARCH"
  umount /mnt/cdrom
  rmdir /mnt/cdrom
  exit 1
fi

# Unmount the ISO and clean up
umount /mnt/cdrom
rmdir /mnt/cdrom

# Check if VirtualBox modules are loaded
if ! dmesg | grep -iq virtualbox; then
  warn "VirtualBox modules are not loaded. Disabling the install-vb-guest-additions service."
  systemctl disable install-vb-guest-additions
  exit 0
fi

log "Guest Additions installation complete. Shutting down the VM..."
systemctl disable install-vb-guest-additions
shutdown -h now
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
APT_QUIET="-qq"
[[ $DEBUG -eq 1 ]] && APT_QUIET=""
readonly APT_QUIET

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

# quiet <command...>: runs the command. Its output is only shown when the command fails, so a
# failed step says why. With DEBUG=1 the output is shown as it comes.
quiet() {
  if [[ $DEBUG -eq 1 ]]; then
    "$@"
    return
  fi
  local output
  output="$(mktemp)"
  if ! "$@" > "$output" 2>&1; then
    cat "$output" >&2
    rm -f "$output"
    return 1
  fi
  rm -f "$output"
}

# apt settings FOR THE BUILD ONLY: no translations and no "recommended" packages, so the build is
# fast and the image is small. scripts/seal-image.sh deletes both files at the end of the build,
# so apt in the VM works like normal Debian (decided by BP, 2026-11-21).
# Because of the second setting, every package the image needs must be named in a list below
# or in assets/*/00-packages. A package that is only "recommended" by another one is not installed.
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
quiet apt-get install -y $APT_QUIET apt-utils locales systemd systemd-sysv

LANG=en_GB.UTF-8

sed -i "s/# *\(${LANG} UTF-8\)/\1/" /etc/locale.gen
# Configure locale early
locale-gen
update-locale LANG=${LANG}

# Later updates of the GRUB package must also refresh the copy of the boot loader in EFI/BOOT,
# the one that starts the VM. Debian only does that when this setting is on. It is set before
# the package is installed, so the package takes it over.
echo "grub-efi-${ARCH} grub2/force_efi_extra_removable boolean true" | debconf-set-selections

log "Installing kernel, bootloader, and utilities"
# Define package lists
# The kernel and the boot loader. (No kernel headers: nothing in the image builds kernel modules.)
KERNEL_PACKAGES=(
  linux-image-${ARCH}
  grub-efi-${ARCH}
  grub-efi-${ARCH}-bin
  grub-common
  grub2-common
)

# Tools, the network (dhcpcd, avahi, mDNS names), the SSH server, and what the console wizard
# and hb-config need (whiptail, kbd).
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
  vim-tiny
  file
  whiptail
  kbd
)

# Helpers for the VM programs:
#   hyperv-daemons     Hyper-V: lets the host see the VM's address and shut it down cleanly
#   qemu-guest-agent   QEMU, UTM, Proxmox: the same. The boot test also talks to the VM through it
#   cloud-guest-utils  growpart, which grows the partition into a larger virtual disk
VIRTUALIZATION_SUPPORT=(
  hyperv-daemons
  qemu-guest-agent
  cloud-guest-utils
)

# Install packages. Every list must install: a name that Debian no longer has stops the build
# and says which one. (The VM helpers were once allowed to fail, all four together and unseen.
# One of them grows the disk, and the boot test needs another.)
quiet apt-get install -y $APT_QUIET "${KERNEL_PACKAGES[@]}"
quiet apt-get install -y $APT_QUIET "${SYSTEM_UTILITIES[@]}"
quiet apt-get install -y $APT_QUIET "${VIRTUALIZATION_SUPPORT[@]}"

log "Setting up GRUB bootloader"
# GRUB's own name for the CPU type. Debian calls 64-bit Intel/AMD "amd64"; GRUB calls it "x86_64".
case "${ARCH}" in
  amd64) GRUB_TARGET="x86_64-efi" ;;
  arm64) GRUB_TARGET="arm64-efi" ;;
  *) error "Unsupported architecture: ${ARCH}"; exit 1 ;;
esac

# The boot loader is installed in two places on the boot partition:
#   - EFI/debian: Debian's own place. The GRUB package only updates the boot partition later
#     when this folder exists.
#   - EFI/BOOT ("removable"): the place every VM program looks in. A VM has no saved boot entry
#     (--no-nvram), so this is the copy that starts the system.
# --force-extra-removable writes both. The setting of the same name (set before the package was
# installed, see above) makes every later update of the GRUB package refresh both as well.
grub-install \
    --target="${GRUB_TARGET}" \
    --efi-directory=/boot/efi \
    --boot-directory=/boot \
    --bootloader-id=debian \
    --no-nvram \
    --force-extra-removable \
    --recheck

# The serial port: ttyS0 on Intel/AMD, ttyAMA0 on ARM VMs.
case "${ARCH}" in
  arm64) SERIAL_CONSOLE="ttyAMA0" ;;
  *) SERIAL_CONSOLE="ttyS0" ;;
esac

# GRUB configuration with serial console and resolution.
#   - The kernel options are in ONE variable. GRUB adds both variables to the kernel line, so
#     the same text in both was passed twice.
#   - The screen (tty0) is the LAST console: the last one gets the start-up messages and the
#     emergency prompt. A serial port still gets the kernel messages and a login prompt.
#   - root=UUID=...: update-grub runs here inside the build, where it can only see the build
#     machine's name for the disk. This option comes later on the kernel line, so it wins.
cat > /etc/default/grub <<GRUB_EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR="Homebridge VM on ${ARCH}"
GRUB_CMDLINE_LINUX_DEFAULT=""
GRUB_CMDLINE_LINUX="console=${SERIAL_CONSOLE} console=tty0 root=UUID=$ROOT_UUID"
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --speed=921600 --unit=0 --word=8 --parity=no --stop=1"
GRUB_GFXMODE=1024x768
GRUB_GFXPAYLOAD_LINUX=keep
GRUB_EOF

update-grub

log "Configuring fstab"
# Create fstab. The last number is the order of the file system check at start: 1 for /, 2 for
# every other file system.
cat > /etc/fstab <<FSTAB_EOF
UUID=$ROOT_UUID / ext4 defaults,noatime 0 1
UUID=$ESP_UUID /boot/efi vfat umask=0077 0 2
FSTAB_EOF

log "Updating initramfs"
# Configure initramfs
echo "RESUME=none" > /etc/initramfs-tools/conf.d/resume
update-initramfs -c -k all

# The build stops when the boot loader is not in both places.
case "${ARCH}" in
  amd64) BOOT_FILES="/boot/efi/EFI/BOOT/BOOTX64.EFI /boot/efi/EFI/debian/grubx64.efi" ;;
  arm64) BOOT_FILES="/boot/efi/EFI/BOOT/BOOTAA64.EFI /boot/efi/EFI/debian/grubaa64.efi" ;;
esac
for BOOT_FILE in $BOOT_FILES; do
  if [[ ! -s "$BOOT_FILE" ]]; then
    error "The boot loader file $BOOT_FILE is missing"
    exit 1
  fi
done

# System configuration
echo "homebridge-vm" > /etc/hostname
cat > /etc/hosts <<HOSTS_EOF
127.0.0.1 localhost
127.0.1.1 homebridge-vm
::1       localhost ip6-localhost ip6-loopback
HOSTS_EOF

# root gets no password: nobody can log in as root. The first-boot wizard makes the user account.

# Clean package cache (scripts/seal-image.sh removes the package lists at the end of the build)
apt-get clean

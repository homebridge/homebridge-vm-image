#!/usr/bin/env bash
set -euxo pipefail

ARCH="$1"
DISTRO="bookworm"
IMG_NAME="homebridge-${ARCH}.img"
SIZE_MB=3072
ESP_SIZE_MB=256

WORKDIR="work-${ARCH}"
ROOTFS="${WORKDIR}/rootfs"
MOUNTDIR="${WORKDIR}/mnt"
ESP_MOUNTDIR="${WORKDIR}/esp"
OUTPUT_DIR="output"

if [[ "$ARCH" != "arm64" && "$ARCH" != "amd64" ]]; then
  echo "Unsupported architecture: $ARCH"
  exit 1
fi

# Clean
sudo rm -rf "$WORKDIR" "$OUTPUT_DIR"
mkdir -p "$ROOTFS" "$MOUNTDIR" "$ESP_MOUNTDIR" "$OUTPUT_DIR"

# Create disk image and partition
IMG_PATH="$OUTPUT_DIR/$IMG_NAME"
dd if=/dev/zero of="$IMG_PATH" bs=1M count="$SIZE_MB"
parted -s "$IMG_PATH" mklabel gpt
parted -s "$IMG_PATH" mkpart ESP fat32 1MiB "${ESP_SIZE_MB}MiB"
parted -s "$IMG_PATH" set 1 esp on
parted -s "$IMG_PATH" mkpart primary ext4 "${ESP_SIZE_MB}MiB" 100%

# Setup loop device
LOOP_DEV=$(sudo losetup --find --partscan --show "$IMG_PATH")
ESP_PART="${LOOP_DEV}p1"
ROOT_PART="${LOOP_DEV}p2"

# Format
sudo mkfs.vfat -F32 "$ESP_PART"
sudo mkfs.ext4 "$ROOT_PART"

# Mount and bootstrap
sudo mount "$ROOT_PART" "$ROOTFS"
sudo debootstrap --arch="$ARCH" --variant=minbase "$DISTRO" "$ROOTFS" http://deb.debian.org/debian

# Mount for chroot
sudo mount --bind /dev "$ROOTFS/dev"
sudo mount --bind /sys "$ROOTFS/sys"
sudo mount --bind /proc "$ROOTFS/proc"

sudo mount "$ESP_PART" "$ESP_MOUNTDIR"
sudo mkdir -p "$ROOTFS/boot/efi"
sudo mount --bind "$ESP_MOUNTDIR" "$ROOTFS/boot/efi"

# Copy Avahi template
sudo mkdir -p "$ROOTFS/root/setup"
sudo cp assets/50-avahi.service "$ROOTFS/root/setup/"

# Copy GRUB modules for amd64
if [ "$ARCH" = "amd64" ]; then
  sudo mkdir -p "$ROOTFS/usr/lib/grub/amd64-efi"
  sudo cp -r /usr/lib/grub/x86_64-efi/* "$ROOTFS/usr/lib/grub/amd64-efi/"
fi

# Run chroot
sudo chroot "$ROOTFS" /bin/bash -eux <<EOF
export DEBIAN_FRONTEND=noninteractive

# Install base and bootloader
apt-get update
apt-get install -y \
  linux-image-$ARCH grub-efi-$ARCH grub-efi-$ARCH-bin \
  grub-common grub2-common \
  systemd systemd-sysv sudo curl gnupg dbus \
  procps net-tools avahi-daemon libavahi-compat-libdnssd-dev \
  ca-certificates \
  build-essential python3 python3-dev python3-setuptools \
  pkg-config git

# Add Homebridge APT repo
curl -fsSL https://repo.homebridge.io/KEY.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/homebridge.gpg
echo 'deb [signed-by=/etc/apt/trusted.gpg.d/homebridge.gpg] https://repo.homebridge.io stable main' > /etc/apt/sources.list.d/homebridge.list

# Install Homebridge
apt-get update
apt-get install -y homebridge

# fstab
echo "/dev/vda2 / ext4 defaults 0 1" > /etc/fstab
echo "/dev/vda1 /boot/efi vfat umask=0077 0 1" >> /etc/fstab

# Enable console
systemctl enable getty@tty1.service
systemctl enable serial-getty@ttyS0.service

# GRUB install
grub-install \
  --target=${ARCH}-efi \
  --efi-directory=/boot/efi \
  --boot-directory=/boot \
  --bootloader-id=debian \
  --no-nvram \
  --removable \
  --recheck

update-grub

# Fallback EFI bootloader (strict + safe)
mkdir -p /boot/efi/EFI/BOOT
BOOT_PATH=\$(find /boot/efi/EFI -type f \\( -name 'grubx64.efi' -o -name 'grubaa64.efi' \\) ! -path '*/BOOT/*' | head -n1)
if [ -n "\$BOOT_PATH" ] && [ -f "\$BOOT_PATH" ]; then
  case "\$BOOT_PATH" in
    *x64*) cp "\$BOOT_PATH" /boot/efi/EFI/BOOT/BOOTX64.EFI ;;
    *aa64*) cp "\$BOOT_PATH" /boot/efi/EFI/BOOT/BOOTAA64.EFI ;;
  esac
else
  echo "⚠️ Could not find a valid GRUB .efi file for fallback boot"
fi

# Set hostname + root password
echo "homebridge-vm" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "127.0.1.1 homebridge-vm" >> /etc/hosts
echo "root:root" | chpasswd

# Enable services
mv /root/setup/50-avahi.service /etc/avahi/services/
systemctl enable homebridge
systemctl enable avahi-daemon

# Clean
apt-get clean
EOF

# Clean exit
sudo chroot "$ROOTFS" /bin/bash -c 'ps -ef || true'
sudo fuser -km "$ROOTFS/dev" || true
sudo fuser -km "$ROOTFS/proc" || true
sudo fuser -km "$ROOTFS/sys" || true

sudo umount -l "$ROOTFS/proc" || true
sudo umount -l "$ROOTFS/sys" || true
sudo umount -l "$ROOTFS/dev" || true
sudo umount -l "$ROOTFS/boot/efi" || true
sudo umount -l "$ROOTFS" || true
sudo umount -l "$ESP_MOUNTDIR" || true
sudo losetup -d "$LOOP_DEV"

# Compress
gzip -f "$IMG_PATH"

echo "✅ Finished: $IMG_PATH.gz"
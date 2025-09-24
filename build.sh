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

# Setup loop device and partitions
LOOP_DEV=$(sudo losetup --find --show "$IMG_PATH")
sudo kpartx -a $LOOP_DEV
sleep 2  # Give udev time to create devices
ESP_PART="/dev/mapper/$(basename $LOOP_DEV)p1"
ROOT_PART="/dev/mapper/$(basename $LOOP_DEV)p2"

for part in "$ESP_PART" "$ROOT_PART"; do
  if [[ ! -b "$part" ]]; then
    echo "ERROR: Partition device $part not found!"
    sudo kpartx -l "$LOOP_DEV"
    ls -l /dev/mapper/
    exit 1
  fi
done

# Format
sudo mkfs.vfat -F32 "$ESP_PART"
sudo mkfs.ext4 "$ROOT_PART"

# Get UUIDs for reliable mounting
ESP_UUID=$(sudo blkid -s UUID -o value "$ESP_PART")
ROOT_UUID=$(sudo blkid -s UUID -o value "$ROOT_PART")

echo "ESP UUID: $ESP_UUID"
echo "Root UUID: $ROOT_UUID"

# Mount and bootstrap
sudo mount "$ROOT_PART" "$ROOTFS"
sudo debootstrap --arch="$ARCH" --variant=buildd "$DISTRO" "$ROOTFS" http://deb.debian.org/debian

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

# Install base and docker-homebridge compatible packages
apt-get update
apt-get upgrade -y
apt-get install -y \
  wget  locales psmisc procps iputils-ping logrotate \
  apt-utils  openssl sudo nano net-tools libnss-mdns \
  linux-image-$ARCH grub-efi-$ARCH grub-efi-$ARCH-bin \
  grub-common grub2-common systemd systemd-sysv dbus \
  gnupg iproute2 hyperv-daemons dhcpcd5 

# fstab with UUIDs for reliable mounting
echo "UUID=$ROOT_UUID / ext4 defaults 0 1" > /etc/fstab
echo "UUID=$ESP_UUID /boot/efi vfat umask=0077 0 1" >> /etc/fstab

# GRUB install
grub-install \
  --target=${ARCH}-efi \
  --efi-directory=/boot/efi \
  --boot-directory=/boot \
  --bootloader-id=debian \
  --no-nvram \
  --removable \
  --recheck

# Configure GRUB with UUID-based root and enhanced serial console
sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"console=tty0 console=ttyS0 root=UUID=$ROOT_UUID loglevel=7\"|" /etc/default/grub
sed -i 's/^GRUB_CMDLINE_LINUX=".*"/GRUB_CMDLINE_LINUX=""/' /etc/default/grub
sed -i 's/^#GRUB_TERMINAL=console/GRUB_TERMINAL="console"/' /etc/default/grub
#sed -i 's/^#GRUB_SERIAL_COMMAND=.*/GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"/' /etc/default/grub

# Add serial console configuration if not present
grep -q "^GRUB_SERIAL_COMMAND=" /etc/default/grub || echo 'GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"' >> /etc/default/grub

# Clean initramfs configuration to avoid loop device references
rm -f /etc/initramfs-tools/conf.d/resume
echo "RESUME=none" > /etc/initramfs-tools/conf.d/resume

# Force clean rebuild of initramfs
update-initramfs -d -k all || true
update-initramfs -c -k all

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

# Final initramfs update
update-initramfs -u

# Clean
apt-get clean

# Debug info
#echo "=== Final fstab ==="
#cat /etc/fstab
#echo "=== GRUB config ==="
#cat /etc/default/grub
#echo "=== Available block devices ==="
#lsblk || true
EOF

install_staged_assets() {
  echo
  echo "=== Installing staged assets for $1 ==="
  local STAGE_ASSET="$1"
  local TARGET_DIR="$2"
  export ROOTFS_DIR="$ROOTFS"
  # Copy config files if present
  if [ -d "assets/$STAGE_ASSET/files" ]; then
    sudo mkdir -p "$ROOTFS/files"
    sudo cp -r "assets/$STAGE_ASSET/files" "$ROOTFS/files"
  fi
  # Install extra packages if 00-packages exists
  if [ -f "assets/$STAGE_ASSET/00-packages" ]; then
    local EXTRA_PKGS
    EXTRA_PKGS=$(grep -v '^#' "assets/$STAGE_ASSET/00-packages" | xargs)
    if [ -n "$EXTRA_PKGS" ]; then
      sudo chroot "$ROOTFS" /bin/bash -c "apt-get update && apt-get install -y $EXTRA_PKGS"
    fi
  fi
  echo "=== Installed extra packages for $1 ==="
  # Run custom script if 01-run.sh exists
  for RUN_SCRIPT in "assets/$STAGE_ASSET"/[0-9][0-9]-run.sh; do
    if [ -f "$RUN_SCRIPT" ]; then
      echo "=== Running staged script: $RUN_SCRIPT ==="
      # sudo cp "$RUN_SCRIPT" "$ROOTFS/tmp/$(basename "$RUN_SCRIPT")"
      # sudo chmod +x "$ROOTFS/tmp/$(basename "$RUN_SCRIPT")"
      # sudo chroot "$ROOTFS" /bin/bash -c "bash /tmp/$(basename "$RUN_SCRIPT")"
      # sudo rm -f "$ROOTFS/tmp/$(basename "$RUN_SCRIPT")"
      (
        on_chroot() {
          sudo chroot "$ROOTFS" /bin/bash -eux "$@"
        }
        cd "assets/$STAGE_ASSET"
        sudo chmod +x "$(basename "$RUN_SCRIPT")"
        export -f on_chroot
        ./$(basename "$RUN_SCRIPT")
      )
      echo "=== Finished staged script: $RUN_SCRIPT ==="
    fi
  done
  echo "=== Finished staged assets for $1 ==="
  echo
}

# Customization from raspbian image 01-homebridge

export FIRST_USER_NAME="homebridge"
export BUILD_VERSION="test build"

install_staged_assets "01-homebridge" "$ROOTFS/etc/nginx"
#install_staged_assets "03-nginx" "$ROOTFS/etc/nginx"
#install_staged_assets "04-tzupdate" "$ROOTFS/etc/nginx"
#install_staged_assets "05-ffmpeg" "$ROOTFS/etc/nginx"
#install_staged_assets "07-other-package" "$ROOTFS/etc/nginx"

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
# gzip -k -f "$IMG_PATH"

echo "✅ Finished: $IMG_PATH.gz"
echo "Root UUID: $ROOT_UUID"
echo "ESP UUID: $ESP_UUID"
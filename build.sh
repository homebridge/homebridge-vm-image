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
  curl wget tzdata locales psmisc procps iputils-ping logrotate \
  libatomic1 apt-transport-https apt-utils jq openssl sudo nano net-tools \
  python3 python3-pip pipx python3-setuptools git make g++ libnss-mdns \
  avahi-discover libavahi-compat-libdnssd-dev python3-venv python3-dev \
  linux-image-$ARCH grub-efi-$ARCH grub-efi-$ARCH-bin \
  grub-common grub2-common systemd systemd-sysv dbus \
  gnupg iproute2 avahi-daemon ca-certificates build-essential \
  pkg-config hyperv-daemons dhcpcd5

# Locale and timezone setup
locale-gen en_US.UTF-8
ln -snf /usr/share/zoneinfo/Etc/GMT /etc/localtime
echo Etc/GMT > /etc/timezone

# Install tzupdate via pipx
pipx install tzupdate || true

# Ensure ping is executable
chmod 0755 /bin/ping

# Add Homebridge APT repo
curl -fsSL https://repo.homebridge.io/KEY.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/homebridge.gpg
echo 'deb [signed-by=/etc/apt/trusted.gpg.d/homebridge.gpg] https://repo.homebridge.io stable main' > /etc/apt/sources.list.d/homebridge.list

# Install Homebridge
apt-get update
apt-get install -y homebridge

# Clean up
apt-get clean
rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*
rm -rf /etc/cron.daily/apt-compat /etc/cron.daily/dpkg /etc/cron.daily/passwd /etc/cron.daily/exim4-base

# Configure networking for automatic DHCP
cat > /etc/systemd/network/10-ethernet.network <<'NETEOF'
[Match]
Name=en* eth*

[Network]
DHCP=yes
IPv6AcceptRA=yes

[DHCP]
RouteMetric=10
UseMTU=true
NETEOF

# Enable networking services
systemctl enable systemd-networkd

# Try to enable systemd-resolved, but don't fail if it doesn't exist
if systemctl list-unit-files | grep -q systemd-resolved; then
    systemctl enable systemd-resolved
    # Create proper resolv.conf symlink (handle busy file)
    umount /etc/resolv.conf 2>/dev/null || true
    rm -f /etc/resolv.conf
    ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
    echo "systemd-resolved configured"
else
    echo "systemd-resolved not available, using traditional DNS"
    # Create basic resolv.conf with public DNS servers
    umount /etc/resolv.conf 2>/dev/null || true
    rm -f /etc/resolv.conf
    cat > /etc/resolv.conf <<'DNSEOF'
# Fallback DNS configuration
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 2001:4860:4860::8888
nameserver 2001:4860:4860::8844
DNSEOF
fi

# Fallback traditional networking (in case systemd-networkd fails)
cat > /etc/network/interfaces <<'IFACEEOF'
# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
auto eth0
iface eth0 inet dhcp

auto ens3
iface ens3 inet dhcp

auto enp0s3
iface enp0s3 inet dhcp
IFACEEOF

# fstab with UUIDs for reliable mounting
echo "UUID=$ROOT_UUID / ext4 defaults 0 1" > /etc/fstab
echo "UUID=$ESP_UUID /boot/efi vfat umask=0077 0 1" >> /etc/fstab

# Enable console services for both TTY and Serial
systemctl enable getty@tty1.service
systemctl enable serial-getty@ttyS0.service

# Configure systemd for serial console logging
mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d
cat > /etc/systemd/system/serial-getty@ttyS0.service.d/override.conf <<'SERIALEOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -- \\u' --keep-baud 115200,57600,38400,9600 %I $TERM
StandardOutput=journal+console
StandardError=journal+console
SERIALEOF

# Configure journald for console output
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/console.conf <<'JOURNALEOF'
[Journal]
ForwardToConsole=yes
TTYPath=/dev/console
MaxLevelConsole=info
JOURNALEOF

# Configure rsyslog for serial console if available
if systemctl list-unit-files | grep -q rsyslog; then
    cat > /etc/rsyslog.d/50-console.conf <<'RSYSLOGEOF'
# Send all logs to console (which includes serial)
*.* /dev/console
RSYSLOGEOF
fi

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
sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"console=tty0 console=ttyS0,115200n8 root=UUID=$ROOT_UUID loglevel=7 systemd.journald.forward_to_console=yes\"|" /etc/default/grub
sed -i 's/^GRUB_CMDLINE_LINUX=".*"/GRUB_CMDLINE_LINUX=""/' /etc/default/grub
sed -i 's/^#GRUB_TERMINAL=console/GRUB_TERMINAL="console serial"/' /etc/default/grub
sed -i 's/^#GRUB_SERIAL_COMMAND=.*/GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"/' /etc/default/grub

# Add serial console configuration if not present
grep -q "^GRUB_SERIAL_COMMAND=" /etc/default/grub || echo 'GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"' >> /etc/default/grub

# Clean initramfs configuration to avoid loop device references
rm -f /etc/initramfs-tools/conf.d/resume
echo "RESUME=none" > /etc/initramfs-tools/conf.d/resume

# Force clean rebuild of initramfs
update-initramfs -d -k all || true
update-initramfs -c -k all

update-grub

cat /etc/default/grub

ls -lR /boot/efi/EFI

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

# Enable services
mv /root/setup/50-avahi.service /etc/avahi/services/
systemctl enable homebridge
systemctl enable avahi-daemon
systemctl enable dhcpcd

# Test network configuration
echo "=== Testing network setup ==="
systemctl status systemd-networkd --no-pager || echo "systemd-networkd not running"
systemctl status systemd-resolved --no-pager || echo "systemd-resolved not running"

# Clean
apt-get clean

# Debug info
echo "=== Final fstab ==="
cat /etc/fstab
echo "=== GRUB config ==="
cat /etc/default/grub
echo "=== Available block devices ==="
lsblk || true
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
echo "Root UUID: $ROOT_UUID"
echo "ESP UUID: $ESP_UUID"
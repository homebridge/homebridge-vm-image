#!/bin/bash -e

#
# Automatic security updates: Debian's unattended-upgrades, security fixes only, never a restart.
# The package is in 00-packages. This stage adds the settings.
#

install -m 644 files/52unattended-upgrades-homebridge "${ROOTFS_DIR}/etc/apt/apt.conf.d/"

# Switch the daily run on. (The package writes the same file when its question is answered
# with yes; writing it here does not depend on that answer.)
cat > "${ROOTFS_DIR}/etc/apt/apt.conf.d/20auto-upgrades" << 'EOF_AUTO'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF_AUTO
chmod 644 "${ROOTFS_DIR}/etc/apt/apt.conf.d/20auto-upgrades"

on_chroot << 'EOF_CHROOT'
set -e

# the build stops when the settings are not the ones meant: one source, and no restart
ORIGINS="$(apt-config dump | grep '^Unattended-Upgrade::Origins-Pattern::')"
[ "$(printf '%s\n' "$ORIGINS" | wc -l)" -eq 1 ]
printf '%s\n' "$ORIGINS" | grep -q 'label=Debian-Security'
apt-config dump | grep -qx 'Unattended-Upgrade::Automatic-Reboot "false";'

systemctl enable apt-daily.timer apt-daily-upgrade.timer
EOF_CHROOT

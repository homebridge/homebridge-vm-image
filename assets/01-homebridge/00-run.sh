#!/bin/bash -e

#
# Install Homebridge and Homebridge Config UI X
#

#
# Executables Files
#

install -m 755 files/hb-config "${ROOTFS_DIR}/usr/local/sbin/hb-config"


# Pre-start files
install -v -d "${ROOTFS_DIR}/etc/hb-service/homebridge/prestart.d"
install -m 755 files/20-hb-nginx-check "${ROOTFS_DIR}/etc/hb-service/homebridge/prestart.d/"

# Start-up tasks that need no person: grow the file system into the virtual disk, and write
# the name of the VM program on the login screen. They run at every start and do nothing when
# there is nothing to do.
install -m 644 files/hb-expand-rootfs.service "${ROOTFS_DIR}/etc/systemd/system/"
install -m 644 files/hb-vm-issue.service "${ROOTFS_DIR}/etc/systemd/system/"

# First boot service: the wizard that makes the user account. It needs a person at the console.
install -m 644 files/first-boot-homebridge.service "${ROOTFS_DIR}/etc/systemd/system/"
install -v -d "${ROOTFS_DIR}/etc/systemd/system/getty@tty1.service.d"
install -m 644 files/getty-tty1-homebridge-setup.conf "${ROOTFS_DIR}/etc/systemd/system/getty@tty1.service.d/10-homebridge-setup.conf"
install -m 755 files/first-boot-homebridge "${ROOTFS_DIR}/usr/local/sbin/"
install -m 755 files/expandVirtualFilesystem "${ROOTFS_DIR}/usr/local/sbin/"
install -m 755 files/updateIssueVMName "${ROOTFS_DIR}/usr/local/sbin/"

# Makes the SSH host keys on the first start (the image holds none, see scripts/seal-image.sh)
install -m 644 files/hb-ssh-host-keys.service "${ROOTFS_DIR}/etc/systemd/system/"
install -m 644 files/hb-machine-id.service "${ROOTFS_DIR}/etc/systemd/system/"

# Lets the Homebridge UI restart and shut down the VM: its two buttons run "sudo -n shutdown".
# The file allows the homebridge user these three commands and nothing else.
install -v -d "${ROOTFS_DIR}/etc/sudoers.d"
install -m 0440 files/010_homebridge-nopasswd "${ROOTFS_DIR}/etc/sudoers.d/"

# VM detection and the image versions: /opt/homebridge/source-vm.sh, the name the Homebridge
# apt package loads
install -v -d "${ROOTFS_DIR}/opt/homebridge/"
install -m 644 files/source-vm.sh "${ROOTFS_DIR}/opt/homebridge/"
#
# MOTD
#

install -m 644 files/issue "${ROOTFS_DIR}/etc/issue"
install -m 755 files/motd-linux "${ROOTFS_DIR}/etc/update-motd.d/15-linux"
install -m 755 files/motd-homebridge "${ROOTFS_DIR}/etc/update-motd.d/20-homebridge"

#
# Set Version
#
echo "$BUILD_VERSION" > "${ROOTFS_DIR}/etc/hb-release"

# The fingerprint of the key that signs the Homebridge package repo (repo.homebridge.io/KEY.gpg).
# Every Homebridge apt user has this key. If it is ever replaced, this value must change with it.
HB_KEY_FINGERPRINT="ACAA60814A7524504F07DE07DF5B0FE88C8F5D92"

on_chroot << EOF

set -e

# The key of the Homebridge package repo is downloaded, and only used when it is the known key.
HB_KEY_TMP=\$(mktemp -d)
export GNUPGHOME="\$HB_KEY_TMP/gnupg"
mkdir -m 700 "\$GNUPGHOME"
curl -sSfL https://repo.homebridge.io/KEY.gpg -o "\$HB_KEY_TMP/KEY.gpg" < /dev/null
HB_KEY_FOUND=\$(gpg --show-keys --with-colons "\$HB_KEY_TMP/KEY.gpg" < /dev/null | awk -F: '\$1 == "fpr" { print \$10; exit }')
if [ "\$HB_KEY_FOUND" != "${HB_KEY_FINGERPRINT}" ]; then
  echo "The key from repo.homebridge.io is not the known Homebridge key (found: \$HB_KEY_FOUND)" >&2
  exit 1
fi
gpg --dearmor < "\$HB_KEY_TMP/KEY.gpg" > /usr/share/keyrings/homebridge.gpg
rm -rf "\$HB_KEY_TMP"
unset GNUPGHOME
echo "deb [signed-by=/usr/share/keyrings/homebridge.gpg] https://repo.homebridge.io ${RELEASE_STREAM} main" > /etc/apt/sources.list.d/homebridge.list

apt-get update < /dev/null
apt-get install -y homebridge=${HOMEBRIDGE_APT_PKG_VERSION} < /dev/null

# empty motd
> /etc/motd

# make a symlink to the main config directory
[ -e /root/.homebridge ] || ln -fs /var/lib/homebridge /root/.homebridge

# set ui port for use in motd message
echo "8581" > /etc/hb-ui-port

# prioritise dns over mdns
sed -i 's/files mdns4_minimal \[NOTFOUND=return\] dns/files dns mdns4_minimal \[NOTFOUND=return\]/' /etc/nsswitch.conf

# Store versions in source-vm.sh
{
  echo "# Appended by 00-run.sh"
  echo "export HOMEBRIDGE_VM_IMAGE_VERSION=${BUILD_VERSION}"
  echo "export FFMPEG_FOR_HOMEBRIDGE_VERSION=${FFMPEG_FOR_HOMEBRIDGE_VERSION}"
  echo "export HOMEBRIDGE_APT_PKG_VERSION=${HOMEBRIDGE_APT_PKG_VERSION}"
} >> /opt/homebridge/source-vm.sh

# the build stops when sudo would refuse its rules
visudo -c > /dev/null

systemctl daemon-reload
systemctl enable homebridge
systemctl enable first-boot-homebridge
systemctl enable hb-ssh-host-keys
systemctl enable hb-machine-id
systemctl enable hb-expand-rootfs
systemctl enable hb-vm-issue
EOF



#
# Automatic security updates: Debian's unattended-upgrades, security fixes only, never a restart.
# The package is in 00-packages; these are its settings.
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

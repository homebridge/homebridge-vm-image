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

# First boot service
install -m 644 files/first-boot-homebridge.service "${ROOTFS_DIR}/etc/systemd/system/"
install -m 755 files/first-boot-homebridge "${ROOTFS_DIR}/usr/local/sbin/"
install -m 755 files/expandVirtualFilesystem "${ROOTFS_DIR}/usr/local/sbin/"
install -m 755 files/updateIssueVMName "${ROOTFS_DIR}/usr/local/sbin/"

# VM detection script

install -v -d "${ROOTFS_DIR}/opt/homebridge/"
install -m 755 files/source-vm.sh "${ROOTFS_DIR}/opt/homebridge/"
#
# MOTD
#

install -m 755 files/issue "${ROOTFS_DIR}/etc/issue"
install -m 755 files/motd-linux "${ROOTFS_DIR}/etc/update-motd.d/15-linux"
install -m 755 files/motd-homebridge "${ROOTFS_DIR}/etc/update-motd.d/20-homebridge"
install -m 633 files/bashrc.partial "${ROOTFS_DIR}/tmp/bashrc.partial"

#
# Set Version
#
echo "$BUILD_VERSION" > "${ROOTFS_DIR}/etc/hb-release"

on_chroot << EOF

set -e

# Original had a sudo tee ....but the build failed with that 'sudo: unable to resolve host b23313a4fe2b: Name or service not known
curl -sSfL https://repo.homebridge.io/KEY.gpg | gpg --dearmor | tee /usr/share/keyrings/homebridge.gpg  > /dev/null
echo "deb [signed-by=/usr/share/keyrings/homebridge.gpg] https://repo.homebridge.io ${RELEASE_STREAM} main" | tee /etc/apt/sources.list.d/homebridge.list > /dev/null

apt-get update
apt-get install homebridge=${HOMEBRIDGE_APT_PKG_VERSION} -y

# empty motd
> /etc/motd

# make a symlink to the main config directory
[ -e /root/.homebridge ] || ln -fs /var/lib/homebridge /root/.homebridge

# include homebridge bashrc in first user's bashrc
rm -rf /tmp/bashrc.partial

# set ui port for use in motd message
echo "8581" > /etc/hb-ui-port

# prioritise dns over mdns
sed -i 's/files mdns4_minimal \[NOTFOUND=return\] dns/files dns mdns4_minimal \[NOTFOUND=return\]/' /etc/nsswitch.conf

# Store versions in source-vm.sh

echo "# Appended by 00-run.sh" | sudo tee -a "/opt/homebridge/source-vm.sh" > /dev/null
echo "export HOMEBRIDGE_VM_IMAGE_VERSION=${BUILD_VERSION}" | sudo tee -a "/opt/homebridge/source-vm.sh" > /dev/null
echo "export FFMPEG_FOR_HOMEBRIDGE_VERSION=${FFMPEG_FOR_HOMEBRIDGE_VERSION}" | sudo tee -a "/opt/homebridge/source-vm.sh" > /dev/null
echo "export HOMEBRIDGE_APT_PKG_VERSION=${HOMEBRIDGE_APT_PKG_VERSION}" | sudo tee -a "/opt/homebridge/source-vm.sh" > /dev/null

systemctl daemon-reload
systemctl enable homebridge
systemctl enable first-boot-homebridge
EOF


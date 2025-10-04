#!/bin/bash -e

#
# Install the tzupdate service to update the timezone on boot
#

install -m 644 files/install-vb-guest-additions.service "${ROOTFS_DIR}/etc/systemd/system/"
install -m 755 files/install-vb-guest-additions.sh "${ROOTFS_DIR}/usr/local/sbin/"

on_chroot << EOF
systemctl daemon-reload
systemctl enable install-vb-guest-additions
EOF

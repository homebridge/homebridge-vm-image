#!/bin/bash -e

#
# Install the vimrc.tiny to enable vi as vi
#

install -v -d "${ROOTFS_DIR}/etc/vim/"
install -m 644 files/vimrc.tiny "${ROOTFS_DIR}/etc/vim/"


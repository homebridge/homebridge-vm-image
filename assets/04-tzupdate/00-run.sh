#!/bin/bash -e

#
# Timezone: looked up once, the first time the VM starts with a network (decided by BP, 2026-11-21).
#
# The tzupdate tool asks public web services where the VM's IP address is. Images up to
# November 2026 ran it at every start, which also overwrote a timezone the user had picked.
# Now hb-timezone-once.service runs it one time only, and not at all when the user already
# picked a timezone.
#

# The exact version of tzupdate and the SHA-256 checksum of its source file on pypi.org.
# To update: pick the version on https://pypi.org/project/tzupdate/#files and copy the checksum
# of the .tar.gz file.
TZUPDATE_VERSION="2.1.0"
TZUPDATE_SHA256="5b55795c390e4ccc90e649c8cc387447daaf30a21d68f7196b49824cbcba8adc"

install -m 755 files/hb-timezone-once "${ROOTFS_DIR}/usr/local/sbin/"
install -m 644 files/hb-timezone-once.service "${ROOTFS_DIR}/etc/systemd/system/"
install -d -m 755 "${ROOTFS_DIR}/var/lib/hb-image"

on_chroot << EOF
set -e

# pip only installs the file when its checksum is the one above. tzupdate needs no other package.
echo "tzupdate==${TZUPDATE_VERSION} --hash=sha256:${TZUPDATE_SHA256}" > /tmp/tzupdate-requirements.txt
pip install --break-system-packages --root-user-action=ignore --no-cache-dir --no-deps --require-hashes -r /tmp/tzupdate-requirements.txt < /dev/null
rm -f /tmp/tzupdate-requirements.txt

/usr/local/bin/tzupdate --help > /dev/null < /dev/null

systemctl enable hb-timezone-once
EOF

#!/usr/bin/env bash
# Takes out of the finished system what must not be the same in every copy of the image.
# build-debian-image.sh runs it as the last step, on the folder that holds the new system.
#
# Usage: seal-image.sh <folder of the new system>
set -euo pipefail

ROOTFS="${1:?usage: seal-image.sh <folder of the new system>}"

if [[ ! -d "$ROOTFS/etc" || "$(realpath "$ROOTFS")" == "/" ]]; then
  echo "seal-image.sh: not the folder of a new system: $ROOTFS" >&2
  exit 1
fi

# The SSH host keys: installing the SSH server makes them. Each VM makes its own on its first
# start (hb-ssh-host-keys.service).
rm -f "$ROOTFS"/etc/ssh/ssh_host_*

# The machine id: installing systemd makes it. An EMPTY file tells systemd to make a new id on
# the first start and to save it. (The file must stay: with no file at all, systemd treats the
# start as a brand new system and switches units on and off by its own defaults.)
: > "$ROOTFS/etc/machine-id"
chmod 444 "$ROOTFS/etc/machine-id"
# D-Bus keeps the same id under another name. It must be a link to the file above, not a copy.
if [[ -e "$ROOTFS/var/lib/dbus/machine-id" && ! -L "$ROOTFS/var/lib/dbus/machine-id" ]]; then
  ln -sf /etc/machine-id "$ROOTFS/var/lib/dbus/machine-id"
fi

# What the build left behind and no VM needs: package lists and downloaded packages (apt fetches
# fresh lists in the VM), build logs, and root's cache folder.
rm -rf "$ROOTFS"/var/lib/apt/lists/*
rm -f "$ROOTFS"/var/cache/apt/archives/*.deb "$ROOTFS"/var/cache/apt/*.bin
rm -f "$ROOTFS/var/log/bootstrap.log" "$ROOTFS/var/log/dpkg.log" "$ROOTFS/var/log/alternatives.log"
rm -f "$ROOTFS"/var/log/apt/*
rm -rf "$ROOTFS/root/.cache"

# The two apt settings that are for the build only (see scripts/chroot-base-setup.sh). Without
# them apt in the VM works like normal Debian: "apt install" brings recommended packages along.
rm -f "$ROOTFS/etc/apt/apt.conf.d/99norecommends" "$ROOTFS/etc/apt/apt.conf.d/99nolang"

# Stop the build when anything above is still there.
LEFT="$(find "$ROOTFS/etc/ssh" -maxdepth 1 -name 'ssh_host_*' 2> /dev/null || true)"
[[ -s "$ROOTFS/etc/machine-id" ]] && LEFT="${LEFT}${LEFT:+$'\n'}$ROOTFS/etc/machine-id (not empty)"
if [[ -n "$LEFT" ]]; then
  echo "seal-image.sh: still in the image:" >&2
  echo "$LEFT" >&2
  exit 1
fi

echo "seal-image.sh: done"

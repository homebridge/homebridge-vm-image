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

# Stop the build when anything above is still there.
LEFT="$(find "$ROOTFS/etc/ssh" -maxdepth 1 -name 'ssh_host_*' 2> /dev/null || true)"
if [[ -n "$LEFT" ]]; then
  echo "seal-image.sh: still in the image:" >&2
  echo "$LEFT" >&2
  exit 1
fi

echo "seal-image.sh: done"

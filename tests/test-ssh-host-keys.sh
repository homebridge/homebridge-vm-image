#!/usr/bin/env bash
# The image must hold no SSH host keys. Each VM makes its own on its first start.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

SEAL="$REPO/scripts/seal-image.sh"

# a new system as the build leaves it: installing the SSH server made the keys
mkdir -p "$W/sys/etc/ssh"
for kind in ecdsa ed25519 rsa; do
  echo "key" > "$W/sys/etc/ssh/ssh_host_${kind}_key"
  echo "key" > "$W/sys/etc/ssh/ssh_host_${kind}_key.pub"
done
echo "keep" > "$W/sys/etc/ssh/sshd_config"

is "the last build step runs" "$SEAL" "$W/sys"
same "no host key is left in the image" "$(find "$W/sys/etc/ssh" -name 'ssh_host_*' | wc -l | tr -d ' ')" "0"
is "the SSH server settings stay" test -f "$W/sys/etc/ssh/sshd_config"
isnt "the step refuses a folder that is not a new system" "$SEAL" "$W/bin"
isnt "the step refuses /" "$SEAL" /
has "the build runs the step" "$REPO/build-debian-image.sh" 'scripts/seal-image.sh" "${ROOTFS}"'

# the unit that makes the keys on the first start
UNIT="$FILES/hb-ssh-host-keys.service"
has "the keys are made before the SSH server starts" "$UNIT" "Before=ssh.service ssh.socket"
has "only missing keys are made" "$UNIT" "ExecStart=/usr/bin/ssh-keygen -A"

run_stage 01-homebridge 00-run.sh
same "the Homebridge stage ends with code 0" "$STAGE_CODE" "0"
is "the stage installs the unit" test -f "$W/root/etc/systemd/system/hb-ssh-host-keys.service"
has "the stage switches the unit on" "$W/chroot-script" "systemctl enable hb-ssh-host-keys"

finish

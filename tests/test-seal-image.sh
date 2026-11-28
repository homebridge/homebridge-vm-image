#!/usr/bin/env bash
# shellcheck disable=SC2016  # single quotes are meant: the text is looked for, or passed on, as it is
# The image must hold no SSH host keys and no machine id. Each VM makes its own on its first start.
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
echo "5e73bc47ca144be7a1879eae0634a37d" > "$W/sys/etc/machine-id"
mkdir -p "$W/sys/var/lib/dbus" && echo "5e73bc47ca144be7a1879eae0634a37d" > "$W/sys/var/lib/dbus/machine-id"

# what a build leaves behind
mkdir -p "$W/sys/var/lib/apt/lists/partial" "$W/sys/var/cache/apt/archives" "$W/sys/var/log/apt" "$W/sys/root/.cache/pip" "$W/sys/etc/apt/apt.conf.d"
echo x > "$W/sys/var/lib/apt/lists/deb.debian.org_debian_dists_trixie_InRelease"
echo x > "$W/sys/var/cache/apt/archives/some_1.0_arm64.deb"
echo x > "$W/sys/var/cache/apt/pkgcache.bin"
echo x > "$W/sys/var/log/bootstrap.log"; echo x > "$W/sys/var/log/dpkg.log"; echo x > "$W/sys/var/log/apt/history.log"
echo x > "$W/sys/root/.cache/pip/file"
echo 'APT::Install-Recommends "false";' > "$W/sys/etc/apt/apt.conf.d/99norecommends"
echo 'Acquire::Languages "none";' > "$W/sys/etc/apt/apt.conf.d/99nolang"
echo 'keep' > "$W/sys/etc/apt/apt.conf.d/52unattended-upgrades-homebridge"

is "the last build step runs" "$SEAL" "$W/sys"
same "no package list is left in the image" "$(find "$W/sys/var/lib/apt/lists" -type f | wc -l | tr -d ' ')" "0"
same "no downloaded package and no apt cache file is left" "$(find "$W/sys/var/cache/apt" -type f | wc -l | tr -d ' ')" "0"
same "no build log is left" "$(find "$W/sys/var/log" -type f | wc -l | tr -d ' ')" "0"
isnt "root's cache folder is gone" test -e "$W/sys/root/.cache"
isnt "the build-only setting 'no recommended packages' is not in the image" test -e "$W/sys/etc/apt/apt.conf.d/99norecommends"
isnt "the build-only setting 'no translations' is not in the image" test -e "$W/sys/etc/apt/apt.conf.d/99nolang"
is "the settings for automatic updates stay" test -f "$W/sys/etc/apt/apt.conf.d/52unattended-upgrades-homebridge"
same "no host key is left in the image" "$(find "$W/sys/etc/ssh" -name 'ssh_host_*' | wc -l | tr -d ' ')" "0"
is "the SSH server settings stay" test -f "$W/sys/etc/ssh/sshd_config"
is "the machine id file is still there (systemd needs the file)" test -f "$W/sys/etc/machine-id"
isnt "the machine id file is empty, so every VM makes its own id" test -s "$W/sys/etc/machine-id"
same "the D-Bus copy of the id is a link to that file" "$(readlink "$W/sys/var/lib/dbus/machine-id")" "/etc/machine-id"
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

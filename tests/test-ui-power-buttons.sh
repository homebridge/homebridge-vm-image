#!/usr/bin/env bash
# The "restart server" and "shut down server" buttons of the Homebridge UI run "sudo -n shutdown"
# as the homebridge user. Without a sudo rule for that, the buttons do nothing.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

RULES="$FILES/010_homebridge-nopasswd"

run_stage 01-homebridge 00-run.sh
same "the Homebridge stage ends with code 0" "$STAGE_CODE" "0"
is "the sudo rules file is installed" test -f "$W/root/etc/sudoers.d/010_homebridge-nopasswd"
same "only root can read it, nobody can write it (440, as sudo asks)" "$(stat -c '%a' "$W/root/etc/sudoers.d/010_homebridge-nopasswd")" "440"
has "the build checks the rules with sudo's own tool" "$W/chroot-script" "visudo -c"

same "the file has one rule" "$(grep -vc '^#' "$RULES")" "1"
same "the rule allows shutdown, reboot and poweroff only, as root, for the homebridge user" "$(grep -v '^#' "$RULES")" \
  "homebridge ALL=(root) NOPASSWD: /sbin/shutdown, /sbin/reboot, /sbin/poweroff, /usr/sbin/shutdown, /usr/sbin/reboot, /usr/sbin/poweroff"
has "the boot test checks the rule in a running VM" "$REPO/scripts/boot-test-checks.sh" "sudo -u homebridge sudo -n -l"

finish

#!/usr/bin/env bash
# The units that run on the first start.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

# unit_value <unit file> <key>: every value of that key, on one line
unit_value() { sed -n "s/^$2=//p" "$1" | tr '\n' ' ' | sed 's/ $//'; }

WIZARD="$FILES/first-boot-homebridge.service"
isnt "the wizard is not ordered after multi-user.target (that made a loop in the start order)" grep -qE '^After=.*multi-user\.target' "$WIZARD"
same "the wizard is ready before the login prompt of the screen console is looked at" "$(unit_value "$WIZARD" Before)" "getty@tty1.service"
same "the wizard runs once logins are allowed" "$(unit_value "$WIZARD" After)" "systemd-user-sessions.service"
same "the wizard is started with the system" "$(unit_value "$WIZARD" WantedBy)" "multi-user.target"
same "the start of the system does not wait for the wizard to end (not a oneshot)" "$(unit_value "$WIZARD" Type)" "simple"
same "the wizard marks the console as in use before it starts" "$(unit_value "$WIZARD" ExecStartPre)" "/usr/bin/touch /run/hb-first-boot-wizard"
same "when the wizard ends, the mark is removed and the login prompt is started" "$(unit_value "$WIZARD" ExecStopPost)" \
  "/usr/bin/rm -f /run/hb-first-boot-wizard -/usr/bin/systemctl --no-block start getty@tty1.service"
same "the login prompt of that console does not start while the mark is there" \
  "$(unit_value "$FILES/getty-tty1-homebridge-setup.conf" ConditionPathExists)" "!/run/hb-first-boot-wizard"
has "the boot test looks for a loop in the start order" "$REPO/scripts/boot-test-checks.sh" "ordering cycle"

# growing the disk and naming the VM program need no person, so they must not wait for the wizard
GROW="$FILES/hb-expand-rootfs.service"
same "the disk is grown before Homebridge and before the wizard" "$(unit_value "$GROW" Before)" "homebridge.service first-boot-homebridge.service"
same "the disk is grown at every start" "$(unit_value "$GROW" WantedBy)" "multi-user.target"
isnt "growing the disk has no first-boot-only condition (a disk can be made larger later)" grep -q '^Condition' "$GROW"
same "the grow unit runs the grow script" "$(unit_value "$GROW" ExecStart)" "/usr/local/sbin/expandVirtualFilesystem"
same "the VM program's name is written before the login prompts" "$(unit_value "$FILES/hb-vm-issue.service" Before)" "getty.target first-boot-homebridge.service"

hasnt "the wizard script no longer grows the disk (it only runs when someone is at the console)" "$FILES/first-boot-homebridge" "expandVirtualFilesystem"
hasnt "the wizard script no longer writes the login screen" "$FILES/first-boot-homebridge" "updateIssueVMName"

run_stage 01-homebridge 00-run.sh
for unit in hb-expand-rootfs hb-vm-issue first-boot-homebridge; do
  is "the stage installs $unit.service" test -f "$W/root/etc/systemd/system/$unit.service"
  has "the stage switches $unit on" "$W/chroot-script" "systemctl enable $unit"
done

is "the stage installs the setting for the login prompt of the screen console" test -f "$W/root/etc/systemd/system/getty@tty1.service.d/10-homebridge-setup.conf"

finish

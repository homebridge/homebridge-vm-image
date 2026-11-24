#!/usr/bin/env bash
# Each VM gets a machine id of its own, even when it was made from a UTM package that carries a
# fixed VM UUID (systemd takes the machine id from that UUID on the first start).
# shellcheck disable=SC2016  # single quotes are meant: that text is looked for as it is
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

SCRIPT="$FILES/hb-machine-id"
UNIT="$FILES/hb-machine-id.service"
fake systemd-id128 'echo 0123456789abcdef0123456789abcdef'

# run_it <machine id> <VM UUID or "none">: runs the script on these files
run_it() {
  printf '%s\n' "$1" > "$W/machine-id"
  if [ "$2" = "none" ]; then rm -f "$W/uuid"; else printf '%s\n' "$2" > "$W/uuid"; fi
  HB_MACHINE_ID_FILE="$W/machine-id" HB_PRODUCT_UUID_FILE="$W/uuid" PATH="$W/bin:$PATH" sh "$SCRIPT" > "$W/out" 2>&1
  code=$?
}

run_it 0ad3d20915024c4db919dfc99d2ed323 0AD3D209-1502-4C4D-B919-DFC99D2ED323
same "the id taken from the VM UUID is replaced" "$(cat "$W/machine-id")" "0123456789abcdef0123456789abcdef"
same "and the script ends with code 0" "$code" "0"

run_it 5e73bc47ca144be7a1879eae0634a37d 0AD3D209-1502-4C4D-B919-DFC99D2ED323
same "an id that is not the VM UUID is kept" "$(cat "$W/machine-id")" "5e73bc47ca144be7a1879eae0634a37d"

run_it 5e73bc47ca144be7a1879eae0634a37d none
same "no VM UUID: the id is kept" "$(cat "$W/machine-id")" "5e73bc47ca144be7a1879eae0634a37d"
same "no VM UUID: ends with code 0" "$code" "0"

is "the script is plain sh" dash -n "$SCRIPT"
unit_value() { sed -n "s/^$2=//p" "$1" | tr '\n' ' ' | sed 's/ $//'; }
same "it is not limited to a first start (an empty machine-id file is not one)" "$(unit_value "$UNIT" ConditionFirstBoot)" ""
same "the new id is written once systemd has saved the id to the disk (before that the file can be a read-only copy)" "$(unit_value "$UNIT" After)" "systemd-machine-id-commit.service"
# systemd-machine-id-commit runs late (after first-boot-complete.target): ordering this unit
# early as well made a loop in the start order, which the boot test found
same "no early ordering (no Before=)" "$(unit_value "$UNIT" Before)" ""
same "the default ordering is kept" "$(unit_value "$UNIT" DefaultDependencies)" ""
same "it is started with the system" "$(unit_value "$UNIT" WantedBy)" "multi-user.target"
has "the image installs the script" "$REPO/assets/01-homebridge/00-run.sh" 'files/hb-machine-id "${ROOTFS_DIR}/usr/local/sbin/"'
has "the image switches the unit on" "$REPO/assets/01-homebridge/00-run.sh" "systemctl enable hb-machine-id"

finish

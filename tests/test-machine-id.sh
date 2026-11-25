#!/usr/bin/env bash
# Each VM gets a machine id of its own, even when it was made from a UTM package that carries a
# fixed VM UUID (systemd takes the machine id from that UUID on the first start).
# shellcheck disable=SC2016  # single quotes are meant: that text is looked for as it is
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

UNIT="$FILES/hb-machine-id.service"
unit_value() { sed -n "s/^$2=//p" "$1" | tr '\n' ' ' | sed 's/ $//'; }
fake systemd-id128 'echo 0123456789abcdef0123456789abcdef'

# the unit's command, as systemd runs it ($$ is a plain $), on files of this test
sed -n "s/^ExecStart=\/bin\/sh -c '\(.*\)'$/\1/p" "$UNIT" | sed -e 's/\$\$/$/g' \
  -e "s#/etc/machine-id#$W/machine-id#g" -e "s#/sys/class/dmi/id/product_uuid#$W/uuid#g" > "$W/cmd.sh"
run_it() { # run_it <machine id> <VM UUID>
  printf '%s\n' "$1" > "$W/machine-id"
  printf '%s\n' "$2" > "$W/uuid"
  PATH="$W/bin:$PATH" sh "$W/cmd.sh" > "$W/out" 2>&1
  code=$?
}

is "the command is plain sh" dash -n "$W/cmd.sh"
run_it 0ad3d20915024c4db919dfc99d2ed323 0AD3D209-1502-4C4D-B919-DFC99D2ED323
same "the id taken from the VM UUID is replaced" "$(cat "$W/machine-id")" "0123456789abcdef0123456789abcdef"
same "and the command ends with code 0" "$code" "0"
run_it 5e73bc47ca144be7a1879eae0634a37d 0AD3D209-1502-4C4D-B919-DFC99D2ED323
same "an id that is not the VM UUID is kept" "$(cat "$W/machine-id")" "5e73bc47ca144be7a1879eae0634a37d"
same "and the command ends with code 0" "$code" "0"

same "it waits until systemd has saved the id (before that the file can be a read-only copy)" "$(unit_value "$UNIT" After)" "systemd-machine-id-commit.service"
same "no early ordering, which made a loop in the start order" "$(unit_value "$UNIT" Before)" ""
same "it is started with the system" "$(unit_value "$UNIT" WantedBy)" "multi-user.target"
has "the image switches the unit on" "$REPO/assets/01-homebridge/00-run.sh" "systemctl enable hb-machine-id"

finish

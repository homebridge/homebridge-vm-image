#!/usr/bin/env bash
# The units that run on the first start.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

# unit_value <unit file> <key>: every value of that key, on one line
unit_value() { sed -n "s/^$2=//p" "$1" | tr '\n' ' ' | sed 's/ $//'; }

WIZARD="$FILES/first-boot-homebridge.service"
isnt "the wizard is not ordered after multi-user.target (that made a loop in the start order)" grep -qE '^After=.*multi-user\.target' "$WIZARD"
same "the wizard runs before the login prompt of the screen console" "$(unit_value "$WIZARD" Before)" "getty@tty1.service"
same "the wizard runs once logins are allowed" "$(unit_value "$WIZARD" After)" "systemd-user-sessions.service"
same "the wizard is started with the system" "$(unit_value "$WIZARD" WantedBy)" "multi-user.target"
has "the boot test looks for a loop in the start order" "$REPO/scripts/boot-test-checks.sh" "ordering cycle"

# every unit file ends with a line end (a file without one breaks tools that add a line)
for unit in "$REPO"/assets/*/files/*.service; do
  same "$(basename "$unit") ends with a line end" "$(tail -c 1 "$unit" | od -An -c | tr -d ' ')" '\n'
done

finish

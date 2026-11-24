#!/usr/bin/env bash
# shellcheck disable=SC2016  # single quotes are meant: that text must reach the fake commands as it is
# The setup wizard: Cancel, names and passwords that can not be used, and commands that fail
# must all end in a clear message, never in a silent stop.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

WIZARD="$FILES/first-boot-homebridge"

# A fake whiptail. Each dialog that asks for text or yes/no takes the next line of $W/answers:
#   a line "CANCEL" = the Cancel button (exit code 1), "YES" / "NO" for a yes/no box,
#   "EMPTY" = OK with nothing typed, any other line = the typed text.
# Message boxes are only written to the log. The wizard asks until it gets a usable answer, so
# a test that runs out of answers would never end: "timeout" stops it, with code 124.
cat > "$W/bin/whiptail" <<FAKE
#!/bin/bash
echo "whiptail \$*" >> "$W/calls.log"
case "\$*" in *--msgbox*) exit 0 ;; esac
n=\$(cat "$W/count" 2>/dev/null || echo 0); n=\$((n + 1)); echo "\$n" > "$W/count"
line=\$(sed -n "\${n}p" "$W/answers")
[ -z "\$line" ] && { echo "the test gave no answer for dialog \$n: \$*" >> "$W/calls.log"; exit 1; }
case "\$line" in
  CANCEL | NO) exit 1 ;;
  YES | EMPTY) exit 0 ;;
  *) printf '%s' "\$line" >&2; exit 0 ;;
esac
FAKE
chmod +x "$W/bin/whiptail"
fake clear
fake sleep
fake id 'echo 0'
fake systemctl
fake userdel
# getent: the users and groups that "exist" are listed in $W/users and $W/groups
fake getent 'grep -qx "$2" "'"$W"'/${1}s" 2>/dev/null'

# wizard <answers...>: runs the wizard with these answers. Sets $code.
wizard() {
  printf '%s\n' "$@" > "$W/answers"
  rm -f "${W:?}/count" "${W:?}/calls.log"
  PATH="$W/bin:$PATH" timeout 20 bash "$WIZARD" > "$W/wizard.log" 2>&1
  code=$?
}
said() { grep -c -- "$1" "$W/calls.log"; }

printf 'root\nhomebridge\n' > "$W/passwd"; mv "$W/passwd" "$W/passwds"
printf 'users\nstaff\nadm\nsudo\n' > "$W/groups"
fake useradd
fake chpasswd 'cat > "'"$W"'/chpasswd-input"'

wizard alice secret12 secret12
same "a good name and password: ends with code 0" "$code" "0"
has "the account is made with sudo rights" "$W/calls.log" "useradd -m -s /bin/bash -G sudo alice"
same "the password is set for that account" "$(cat "$W/chpasswd-input")" "alice:secret12"
has "the wizard is switched off afterwards" "$W/calls.log" "systemctl disable first-boot-homebridge"
# systemd prints "Started ..." on the console while the system starts: the wizard waits for the
# start to finish before it draws, so those lines do not land on top of its first screen
same "the wizard waits for the system start before its first screen" \
  "$(grep -n -E 'systemctl is-system-running --wait|whiptail' "$W/calls.log" | head -n 1 | grep -c 'is-system-running')" "1"
has "the user is told it worked" "$W/calls.log" "User 'alice' created successfully"

wizard CANCEL YES
same "Cancel at the name, then yes to leave: ends with code 0 (the wizard comes back at the next start)" "$code" "0"
has "Cancel asks before leaving" "$W/calls.log" "Leave the setup?"
has "leaving says what to do next" "$W/wizard.log" "Restart the VM to run the setup again"
same "leaving makes no account" "$(said '^useradd')" "0"
same "leaving does not switch the wizard off" "$(said 'systemctl disable')" "0"

wizard CANCEL NO alice secret12 secret12
same "Cancel, then no: the setup carries on" "$(said '^useradd -m')" "1"

wizard alice CANCEL NO secret12 secret12
same "Cancel at the password, then no: the setup carries on" "$(said '^useradd -m')" "1"

wizard users bob secret12 secret12
has "a name that is an existing group is refused with a reason" "$W/calls.log" "already in use by the system (as a group)"
has "after that the next name is used" "$W/calls.log" "useradd -m -s /bin/bash -G sudo bob"
same "the group name itself never reaches useradd" "$(said 'useradd.* users$')" "0"

wizard root Bob 9lives EMPTY carol secret12 secret12
same "an existing user, capital letters, a leading digit and an empty name are all refused" "$(said 'The user name can not be used')" "4"
has "the text of the length rule is a full sentence" "$W/calls.log" "The length must be between 1 and 32 characters."
has "then a good name is used" "$W/calls.log" "useradd -m -s /bin/bash -G sudo carol"

wizard alice secret12 secret13 short short 'with:colon' 'with:colon' secret12 secret12
same "passwords that differ are refused" "$(said 'Passwords do not match')" "1"
same "a short password and one with a colon are refused with a reason" "$(said 'The password can not be used')" "2"
same "the account is made once, with the good password" "$(cat "$W/chpasswd-input")" "alice:secret12"

wizard Bad1 Bad2 Bad3 Bad4 erin x x y y z z w w secret12 secret12
same "more than three wrong tries do not end the setup" "$code" "0"
has "the try after them works" "$W/calls.log" "useradd -m -s /bin/bash -G sudo erin"

# useradd fails for the first name, works for the second
fake useradd 'case "$*" in *alice) echo "useradd: cannot lock /etc/passwd" >&2; exit 1 ;; esac'
wizard alice secret12 secret12 dave secret12 secret12
has "a failed useradd is shown with its reason" "$W/calls.log" "could not be made"
has "the reason from useradd is in the message" "$W/calls.log" "cannot lock /etc/passwd"
has "the setup then asks again and makes the next account" "$W/calls.log" "User 'dave' created successfully"
fake useradd

# the password can not be set: the half-made account must be removed again
fake chpasswd 'cat > /dev/null; echo "chpasswd: failure" >&2; exit 1'
wizard alice secret12 secret12 CANCEL YES
has "when the password can not be set, the account is removed again" "$W/calls.log" "userdel -r alice"
same "and the wizard is not switched off" "$(said 'systemctl disable')" "0"

is "the wizard is valid bash" bash -n "$WIZARD"

finish

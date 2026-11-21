#!/usr/bin/env bash
# shellcheck disable=SC2016  # single quotes are meant: that text must reach the script under test as it is
# The timezone is looked up once, the first time the VM starts with a network, and never when
# the user already picked one (decided by BP, 2026-11-21).
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

SCRIPT="$REPO/assets/04-tzupdate/files/hb-timezone-once"
UNIT="$REPO/assets/04-tzupdate/files/hb-timezone-once.service"
R="$W/root"
DONE="$R/var/lib/hb-image/timezone-set-once"

# fresh <timezone the system has> <answer of the lookup | FAIL>
fresh() {
  rm -rf "${R:?}" "${W:?}/calls.log" "${W:?}/bin"
  mkdir -p "$W/bin" "$R/var/lib/hb-image" "$R/usr/share/zoneinfo/Europe" "$R/usr/share/zoneinfo/America" "$R/usr/local/bin"
  touch "$R/usr/share/zoneinfo/Europe/London" "$R/usr/share/zoneinfo/Europe/Berlin" "$R/usr/share/zoneinfo/America/New_York"
  if [ "$2" = "FAIL" ]; then
    printf '#!/bin/sh\necho "tzupdate $*" >> "%s/calls.log"\nexit 1\n' "$W" > "$R/usr/local/bin/tzupdate"
  else
    printf '#!/bin/sh\necho "tzupdate $*" >> "%s/calls.log"\nprintf "%%s\\n" "%s"\n' "$W" "$2" > "$R/usr/local/bin/tzupdate"
  fi
  chmod +x "$R/usr/local/bin/tzupdate"
  fake timedatectl "case \"\$1\" in show) echo '$1' ;; esac; exit 0"
  fake sleep
  in_sandbox "$SCRIPT" > "$W/timezone-once"
}
start() { ( PATH="$W/bin:$PATH" dash "$W/timezone-once" ) > "$W/start.log" 2>&1; }
lookups() { calls | grep -c '^tzupdate' || true; }
sets() { calls | sed -n 's/^timedatectl set-timezone //p' | tr '\n' ' '; }

fresh UTC America/New_York
start
same "first start with a network: the timezone is looked up once" "$(lookups)" "1"
same "and set to the answer" "$(sets)" "America/New_York "
is "and it is written down that this is done" test -s "$DONE"
has "the lookup only prints the timezone, with a 10 second limit" "$W/calls.log" "tzupdate --print-only --timeout 10"

rm -f "${W:?}/calls.log"
start
start
same "every later start: nothing is looked up or changed" "$(lookups):$(sets)" "0:"

fresh Etc/UTC America/New_York
start
same "the other name of the image's timezone (Etc/UTC) counts as 'not picked' too" "$(sets)" "America/New_York "

fresh Europe/Berlin America/New_York
start
same "a timezone the user picked: nothing is looked up" "$(lookups)" "0"
same "a timezone the user picked: it is not changed" "$(sets)" ""
is "a timezone the user picked: it is written down, so there is never a lookup later" test -s "$DONE"

fresh UTC FAIL
start
same "no internet: the lookup is tried six times in that start" "$(lookups)" "6"
same "no internet: nothing is changed" "$(sets)" ""
isnt "no internet: it is not written down as done" test -e "$DONE"
printf '#!/bin/sh\necho "tzupdate $*" >> "%s/calls.log"\necho Europe/Berlin\n' "$W" > "$R/usr/local/bin/tzupdate"
start
same "the next start tries again and sets the timezone" "$(sets)" "Europe/Berlin "

for answer in 'Mars/Olympus_Mons' '../../etc/passwd' '/etc/passwd' 'Europe/London; reboot' 'Europe/Lon don' '$(reboot)'; do
  fresh UTC "$answer"
  start
  same "an answer that is not a real timezone ('$answer') is not used" "$(sets)" ""
  isnt "and it is not written down as done ('$answer')" test -e "$DONE"
done

is "dash accepts the script" dash -n "$SCRIPT"

# the unit: it must stop running for good once the lookup is done
has "the unit does not run once the lookup is done" "$UNIT" "ConditionPathExists=!/var/lib/hb-image/timezone-set-once"
has "the unit waits for the network" "$UNIT" "After=network-online.target"

# the build step
RUN="$REPO/assets/04-tzupdate/00-run.sh"
is "the build installs one exact tzupdate version with its checksum" grep -qE 'tzupdate==\$\{TZUPDATE_VERSION\} --hash=sha256:\$\{TZUPDATE_SHA256\}' "$RUN"
has "pip must refuse a file with another checksum" "$RUN" "--require-hashes"
has "pip leaves no cache in the image" "$RUN" "--no-cache-dir"
isnt "no service runs tzupdate at every start any more" grep -rq 'tzupdate.service\|systemctl enable tzupdate$' "$REPO/assets"

run_stage 04-tzupdate 00-run.sh
same "the timezone stage ends with code 0" "$STAGE_CODE" "0"
same "the lookup script is installed as a program (755)" "$(stat -c '%a' "$W/root/usr/local/sbin/hb-timezone-once")" "755"
has "the stage switches the one-time unit on" "$W/chroot-script" "systemctl enable hb-timezone-once"

finish

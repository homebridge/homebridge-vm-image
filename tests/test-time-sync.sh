#!/usr/bin/env bash
# The VM must keep its clock right by itself: the time sync service has to be in the image.
# (Debian only "recommends" it, and the build installs no recommended packages.)
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

base_setup arm64
same "the base setup ends with code 0" "$BASE_SETUP_CODE" "0"
is "the base setup installs systemd-timesyncd" grep -qE '^apt-get install .* systemd-timesyncd( |$)' "$W/calls.log"
isnt "no package list names ntpdate (a tool that nothing ran)" grep -rqw ntpdate "$REPO/scripts/chroot-base-setup.sh" "$REPO/assets/01-homebridge/00-packages"
has "the boot test checks that time sync is in use" "$REPO/scripts/boot-test-checks.sh" 'timedatectl show -p NTP --value'

finish

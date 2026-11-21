#!/usr/bin/env bash
# What root loads must belong to root. The Homebridge apt package gives /opt/homebridge to the
# user Homebridge and its plugins run as, so the VM detection and the image versions live in a
# root-owned file outside that folder.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

run_stage 01-homebridge 00-run.sh
same "the Homebridge stage ends with code 0" "$STAGE_CODE" "0"

ENV_FILE="$W/root/usr/local/lib/homebridge-vm/vm-env.sh"
LOADER="$W/root/opt/homebridge/source-vm.sh"
is "the file with the settings is installed outside /opt/homebridge" test -f "$ENV_FILE"
is "the name the apt package loads is still there" test -f "$LOADER"
same "that file only loads the root-owned one (its lines that are not comments)" \
  "$(grep -v '^#' "$LOADER" | tr -s ' \n' ' ')" "if [ -r /usr/local/lib/homebridge-vm/vm-env.sh ]; then . /usr/local/lib/homebridge-vm/vm-env.sh fi "
is "the loader is plain sh" dash -n "$LOADER"

has "the image versions are written to the root-owned file" "$W/chroot-script" ">> /usr/local/lib/homebridge-vm/vm-env.sh"
hasnt "nothing is appended to the file in /opt/homebridge" "$W/chroot-script" '"/opt/homebridge/source-vm.sh"'
hasnt "the stage does not call sudo inside the new system" "$W/chroot-script" "| sudo "

has "the login screen script loads the root-owned file" "$FILES/updateIssueVMName" "source /usr/local/lib/homebridge-vm/vm-env.sh"
isnt "no script of this repo that runs as root loads a file from /opt/homebridge" \
  grep -rnE '^[[:space:]]*(source|\.)[[:space:]]+/opt/homebridge/' "$FILES/updateIssueVMName" "$FILES/first-boot-homebridge" "$FILES/expandVirtualFilesystem" "$FILES/hb-config" "$FILES/20-hb-nginx-check"

finish

#!/usr/bin/env bash
# The UTM package. The packaging itself needs a Mac with UTM, so only its pure parts are tested.
# shellcheck disable=SC2016  # single quotes are meant: the text is looked for as it is
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

SCRIPT="$REPO/scripts/package-for-utm.sh"

# the function as it is in the script
eval "$(sed -n '/^random_mac_address() {$/,/^}$/p' "$SCRIPT")"

FIRST="$(random_mac_address)"
SECOND="$(random_mac_address)"
is "the network card address has the right form" grep -qE '^([0-9A-F]{2}:){5}[0-9A-F]{2}$' <<< "$FIRST"
isnt "two packages do not get the same address" test "$FIRST" = "$SECOND"

# 200 addresses: the first byte must always be a made-up, single-machine address (x2, x6, xA or xE)
bad=0
for _ in $(seq 200); do
  case "$(random_mac_address)" in ?[26AE]:*) ;; *) bad=$((bad + 1)) ;; esac
done
same "the first byte always marks a made-up address for one machine" "$bad" "0"

# the notes of the VM are put inside double quotes for PlistBuddy: quotes and backslashes in
# the manifest must be escaped, each one once
ESCAPE="$(sed -n 's/^ *manifest_content=\$(\(sed .*\) "\${MANIFEST}")$/\1/p' "$SCRIPT")"
printf 'say "hi" and a \\ sign\n' > "$W/manifest"
same "a quote and a backslash in the notes are each escaped once" "$(eval "$ESCAPE" '"$W/manifest"')" 'say \"hi\" and a \\ sign'
hasnt "the packaging uses no fixed file name in /tmp" "$SCRIPT" "/tmp/"

has "the packaging writes a new address into the VM config" "$SCRIPT" 'Set :Network:0:MacAddress $(random_mac_address)'

# the template of the VM settings (a property list; python reads it)
TEMPLATE="$REPO/assets/template-utm-config.plist"
python3 - "$TEMPLATE" > "$W/plist-facts" <<'PYTHON'
import plistlib, sys
with open(sys.argv[1], "rb") as handle:
    config = plistlib.load(handle)
print("debug-log", config["QEMU"]["DebugLog"])
print("icon", config["Information"]["Icon"])
print("network-mode", config["Network"][0]["Mode"])
print("uefi", config["QEMU"]["UEFIBoot"])
PYTHON
same "the template is a valid property list" "$?" "0"
has "UTM does not write a debug log for every run of the VM" "$W/plist-facts" "debug-log False"
has "the icon name in the template is a file name" "$W/plist-facts" "icon homebridge-icon.png"
has "the VM is on the home network (bridged), which HomeKit needs" "$W/plist-facts" "network-mode Bridged"

finish

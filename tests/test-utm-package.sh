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

has "the packaging writes a new address into the VM config" "$SCRIPT" 'Set :Network:0:MacAddress $(random_mac_address)'

finish

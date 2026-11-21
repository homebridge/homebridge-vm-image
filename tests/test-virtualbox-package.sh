#!/usr/bin/env bash
# shellcheck disable=SC2016  # single quotes are meant: the text is looked for as it is
# The VirtualBox package. The packaging itself needs VirtualBox, so these read the script.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

SCRIPT="$REPO/scripts/package-for-virtual-box.sh"

is "the script is valid bash" bash -n "$SCRIPT"
has "shared clipboard is off (it needs guest additions, which the image does not have)" "$SCRIPT" "--clipboard-mode disabled"
has "drag and drop is off, for the same reason" "$SCRIPT" "--draganddrop disabled"
hasnt "no sharing option is switched on" "$SCRIPT" "bidirectional"
has "the system type for Intel/AMD is one VirtualBox knows" "$SCRIPT" 'os_type="Debian_64"'
has "the system type for ARM is one VirtualBox knows" "$SCRIPT" 'os_type="Debian_arm64"'
hasnt "the made-up system type names are gone" "$SCRIPT" 'Debian12_${ARCH}'
isnt "the unused guest additions code is deleted" test -e "$REPO/unused_assets"
isnt "nothing in the repo points at the guest additions unit any more" grep -rq "install-vb-guest-additions" "$REPO/README.md" "$REPO/assets" "$REPO/scripts" "$REPO/build-debian-image.sh"

finish

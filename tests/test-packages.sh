#!/usr/bin/env bash
# shellcheck disable=SC2016  # single quotes are meant: the text is looked for, or passed on, as it is
# The package lists of the image: nothing that is unused, empty or gone from Debian 13.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

BASE="$REPO/scripts/chroot-base-setup.sh"

# every package name the image build asks for: the three lists of the base setup and the stage lists
names() {
  { sed -n '/^[A-Z_]*=($/,/^)$/p' "$BASE" | grep -E '^  ["a-z0-9]' ; grep -hv '^#' "$REPO"/assets/*/00-packages; } | tr -d ' "' | sed 's/\${ARCH}/ARCH/' | sort
}
names > "$W/names"

for gone in linux-headers-ARCH spice-vdagent software-properties-common dialog ntpdate; do
  isnt "not installed any more (nothing uses it): $gone" grep -qx "$gone" "$W/names"
done
for empty in apt-transport-https gnupg-agent; do
  isnt "not installed any more (an empty hand-over package): $empty" grep -qx "$empty" "$W/names"
done
isnt "the old name dhcpcd5 is not used" grep -qx dhcpcd5 "$W/names"
isnt "the name with a dot (vim.tiny) is not used" grep -qxF 'vim.tiny' "$W/names"
for needed in linux-image-ARCH grub-efi-ARCH systemd-timesyncd dhcpcd ssh whiptail cloud-guest-utils qemu-guest-agent hyperv-daemons unattended-upgrades nginx jq curl ca-certificates python3-pip sudo; do
  is "still installed: $needed" grep -qx "$needed" "$W/names"
done
same "no package is named twice" "$(uniq -d "$W/names" | tr '\n' ' ')" ""

# every line of a stage list is a package name or a comment (the build drops lines that start with #)
same "the stage lists hold only names and comments" "$(cat "$REPO"/assets/*/00-packages | grep -cvE '^(#.*|[a-z0-9][a-z0-9+.-]*)$')" "0"

base_setup arm64
same "the base setup ends with code 0" "$BASE_SETUP_CODE" "0"
isnt "the base setup does not ask apt for a package that is commented out" grep -qE '^apt-get install .* #' "$W/calls.log"

finish

#!/usr/bin/env bash
# The image must be built on the current Debian release and must know the Debian sources for
# updates and security fixes. With only the source that debootstrap leaves, a VM never gets a
# security fix.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

same "the image is built on Debian 13 (trixie)" "$(sed -n 's/^readonly DISTRO="\(.*\)"$/\1/p' "$REPO/build-debian-image.sh")" "trixie"

base_setup arm64
same "the base setup ends with code 0" "$BASE_SETUP_CODE" "0"

SOURCES="$W/root/etc/apt/sources.list.d/debian.sources"
is "the Debian sources file is written" test -s "$SOURCES"
has "it has the release and its updates" "$SOURCES" "Suites: trixie trixie-updates"
has "it has the security fixes" "$SOURCES" "Suites: trixie-security"
has "the security fixes come from the security server" "$SOURCES" "URIs: https://deb.debian.org/debian-security"
isnt "the one-line file from debootstrap is gone (no source is listed twice)" test -e "$W/root/etc/apt/sources.list"

same "the lists are read and the system is brought up to date before anything is installed" \
  "$(calls | grep '^apt-get' | head -n 3 | sed -n '1p;2p' | tr '\n' ';')" "apt-get update;apt-get -y dist-upgrade;"

# names that Debian 13 no longer has stop the build
for gone in software-properties-common ntpdate dhcpcd5; do
  isnt "the package lists do not name $gone" grep -rqx -- "  $gone\|$gone" "$REPO/scripts/chroot-base-setup.sh" "$REPO/assets/01-homebridge/00-packages" "$REPO/assets/07-other-packages/00-packages"
done

finish

#!/usr/bin/env bash
# The base system (the first packages of every image) must only be used when Debian's signature
# on it is good. A build machine without Debian's key file must stop the build.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

BUILD="$REPO/build-debian-image.sh"

# setup_rootfs() as it is in the build script, with fake tools around it
fake sudo 'exec "$@"'
fake mount
fake debootstrap
fake tar
fake du 'echo "1M x"'
fake zstd
(
  PATH="$W/bin:$PATH"
  # shellcheck disable=SC2317  # called by the function under test
  # shellcheck disable=SC2329 # a stub, called by the code under test
  log() { :; }
  # shellcheck disable=SC2317
  # shellcheck disable=SC2329 # a stub, called by the code under test
  info() { :; }
  # shellcheck disable=SC2317
  # shellcheck disable=SC2329 # a stub, called by the code under test
  warn() { :; }
  eval "$(sed -n 's/^readonly \(DISTRO\|DEBIAN_KEYRING\)=/\1=/p' "$BUILD")"
  eval "$(sed -n '/^setup_rootfs() {$/,/^}$/p' "$BUILD")"
  # shellcheck disable=SC2034  # read by setup_rootfs
  ARCH=arm64 CACHE_DIR="$W/cache" ROOT_PART=/dev/null ROOTFS="$W/rootfs" GITHUB_ACTIONS=true
  mkdir -p "$W/cache" "$W/rootfs"
  setup_rootfs arm64
) > "$W/setup.log" 2>&1
same "the base system step runs" "$?" "0"

CALL="$(calls | grep '^debootstrap')"
case "$CALL" in *" --force-check-gpg "*) ok "debootstrap must check the signature (no check = stop)" ;; *) fail "debootstrap must check the signature (no check = stop)" "$CALL" ;; esac
case "$CALL" in *" --keyring=/usr/share/keyrings/debian-archive-keyring.gpg "*) ok "debootstrap is given Debian's key file" ;; *) fail "debootstrap is given Debian's key file" "$CALL" ;; esac
case "$CALL" in *" https://deb.debian.org/debian") ok "the base system is downloaded over https" ;; *) fail "the base system is downloaded over https" "$CALL" ;; esac
case "$CALL" in *" trixie "*) ok "the base system is Debian 13" ;; *) fail "the base system is Debian 13" "$CALL" ;; esac

has "the build machine gets Debian's key file, and the certificates for https" "$REPO/scripts/install-build-deps.sh" "debootstrap debian-archive-keyring ca-certificates"
has "installing the packages fails when the key file is missing" "$REPO/scripts/install-build-deps.sh" "test -s /usr/share/keyrings/debian-archive-keyring.gpg"

finish

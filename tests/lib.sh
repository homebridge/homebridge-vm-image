#!/usr/bin/env bash
# Shared helpers for the tests in this folder.
#
# How the tests work:
#   - a test copies a file from the repo into a scratch folder,
#   - rewrites the system paths in it (/etc/..., /var/...) to the scratch folder,
#   - puts fake commands (systemctl, curl, apt-get ...) first on the PATH,
#   - runs it, and looks at the result.
# Nothing on the machine that runs the tests is changed. No root rights are needed.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034  # used by the tests
FILES="$REPO/assets/01-homebridge/files"

W="$(mktemp -d)"
trap 'rm -rf "${W:?}"' EXIT
mkdir -p "$W/bin"

CHECKS=0
FAILED=0

ok() {
  CHECKS=$((CHECKS + 1))
  printf '  ok    %s\n' "$1"
}

fail() {
  CHECKS=$((CHECKS + 1))
  FAILED=$((FAILED + 1))
  printf '  FAIL  %s\n' "$1"
  shift
  [ $# -gt 0 ] && printf '        %s\n' "$@"
  return 0
}

# is <text> <command...>: passes when the command succeeds
is() {
  local text="$1"
  shift
  if "$@" >/dev/null 2>&1; then ok "$text"; else fail "$text" "command failed: $*"; fi
}

# isnt <text> <command...>: passes when the command fails
isnt() {
  local text="$1"
  shift
  if "$@" >/dev/null 2>&1; then fail "$text" "command passed but must fail: $*"; else ok "$text"; fi
}

# same <text> <actual> <expected>
same() {
  if [ "$2" = "$3" ]; then ok "$1"; else fail "$1" "expected: $3" "actual:   $2"; fi
}

# has <text> <file> <fixed text that must be in the file>
has() {
  if grep -qF -- "$3" "$2"; then ok "$1"; else fail "$1" "not found in $2: $3"; fi
}

# hasnt <text> <file> <fixed text that must not be in the file>
hasnt() {
  if grep -qF -- "$3" "$2"; then fail "$1" "found in $2: $3"; else ok "$1"; fi
}

# fake <name> [shell lines]: makes a fake command. Every call is written to $W/calls.log as
# "<name> <arguments>". Extra shell lines can set the output and the exit code.
fake() {
  local name="$1"
  shift
  {
    printf '#!/bin/sh\n'
    printf 'echo "%s $*" >> "%s/calls.log"\n' "$name" "$W"
    [ $# -gt 0 ] && printf '%s\n' "$@"
  } > "$W/bin/$name"
  chmod +x "$W/bin/$name"
}

calls() {
  [ -f "$W/calls.log" ] && cat "$W/calls.log"
  return 0
}

# in_sandbox <file>: prints the file with the system paths in it moved into $W/root
in_sandbox() {
  sed -E "s#(^|[[:space:]=\"'>\[(])/(etc|usr|opt|boot|proc|var|run|sys)/#\\1$W/root/\\2/#g" "$1"
}

finish() {
  if [ "$FAILED" -gt 0 ]; then
    printf '  %s of %s checks failed\n' "$FAILED" "$CHECKS"
    exit 1
  fi
  exit 0
}

# base_setup [arch]: runs scripts/chroot-base-setup.sh (the script the build runs inside the new
# system) with its system paths moved into $W/root and with fake package and boot tools.
# The calls are in $W/calls.log, the output in $W/base-setup.log, the exit code in $BASE_SETUP_CODE.
base_setup() {
  rm -rf "${W:?}/root" "${W:?}/calls.log"
  mkdir -p "$W/root/etc/apt/apt.conf.d" "$W/root/etc/apt/sources.list.d" "$W/root/etc/initramfs-tools/conf.d" \
    "$W/root/etc/default" "$W/root/etc/ssh" "$W/root/boot/efi/EFI" "$W/root/var/lib/apt/lists" "$W/root/usr/share/keyrings"
  printf 'VERSION_CODENAME=trixie\n' > "$W/root/etc/os-release"
  printf '# en_GB.UTF-8 UTF-8\n' > "$W/root/etc/locale.gen"
  echo "deb http://deb.debian.org/debian trixie main" > "$W/root/etc/apt/sources.list"
  local tool
  for tool in apt-get locale-gen update-locale grub-install update-grub update-initramfs debconf-set-selections systemctl; do
    [ -x "$W/bin/$tool" ] || fake "$tool"
  done
  in_sandbox "$REPO/scripts/chroot-base-setup.sh" > "$W/chroot-base-setup.sh"
  PATH="$W/bin:$PATH" bash -eu "$W/chroot-base-setup.sh" "${1:-arm64}" ROOT-UUID ESP-UUID 0 > "$W/base-setup.log" 2>&1
  BASE_SETUP_CODE=$?
}

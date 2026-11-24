#!/usr/bin/env bash
# shellcheck disable=SC2016  # single quotes are meant: the text is looked for as it is
# build-debian-image.sh: what happens with wrong arguments, with a failed build, and with a
# version file that has no usable version.
# shellcheck disable=SC2030,SC2031  # the build script is loaded in subshells on purpose: nothing it sets may leak into the test
# shellcheck disable=SC2317  # the stand-in functions are called by the functions under test
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

BUILD="$REPO/build-debian-image.sh"

# every call of sudo is written down (a real build would use it for loop devices and mounts)
fake sudo
plain() { sed 's/\x1b\[[0-9;]*m//g'; }

# ---- wrong arguments: one clear message, exit code 1, and the clean-up changes nothing
( cd "$W" && PATH="$W/bin:$PATH" bash "$BUILD" ) > "$W/no-args.log" 2>&1
same "no argument: ends with code 1" "$?" "1"
has "no argument: says how to call the script" "$W/no-args.log" "Usage:"
hasnt "no argument: the clean-up does not fail on a variable that is not set" "$W/no-args.log" "unbound variable"

( cd "$W" && PATH="$W/bin:$PATH" bash "$BUILD" arm64 nightly ) > "$W/bad-stream.log" 2>&1
same "a stream it does not know: ends with code 1" "$?" "1"
has "a stream it does not know: says so" "$W/bad-stream.log" "Invalid release stream: nightly"
hasnt "a stream it does not know: no 'unbound variable'" "$W/bad-stream.log" "unbound variable"

( cd "$W" && PATH="$W/bin:$PATH" bash "$BUILD" riscv64 stable ) > "$W/bad-arch.log" 2>&1
same "a CPU type it does not know: ends with code 1" "$?" "1"
has "a CPU type it does not know: says which" "$W/bad-arch.log" "Unsupported architecture: riscv64"
same "after a wrong argument nothing is run as root (no 'zero the free space' step)" "$(calls | grep -c '^sudo')" "0"

# ---- the functions of the script, loaded without running a build
load_build() {
  # shellcheck disable=SC1090  # the build script, loaded for its functions
  source "$BUILD"
  trap - EXIT INT TERM
  set +e +u +o pipefail
}

# the clean-up after a FAILED build must not touch the images; after a good build it does
(
  load_build
  cleanup() { :; }
  OUTPUT_DIR="$W/out"; mkdir -p "$OUTPUT_DIR"; : > "$OUTPUT_DIR/x.img"
  eval "$(sed -n '/^cleanup() {$/,/^}$/p' "$BUILD")"
  # shellcheck disable=SC2329 # a stub, called by the code under test
  zero_free_blocks() { echo "ZEROED"; }
  ( exit 1; ) ; ( false; cleanup ) 2>&1 | plain
) > "$W/cleanup-failed.log" 2>&1
hasnt "after a failed build the 'zero the free space' step is skipped" "$W/cleanup-failed.log" "ZEROED"
has "after a failed build the failure is reported" "$W/cleanup-failed.log" "Build failed with exit code 1"
(
  load_build
  OUTPUT_DIR="$W/out"
  # shellcheck disable=SC2329 # a stub, called by the code under test
  zero_free_blocks() { echo "ZEROED"; }
  ( true; cleanup ) 2>&1 | plain
) > "$W/cleanup-ok.log" 2>&1
has "after a good build the free space is zeroed" "$W/cleanup-ok.log" "ZEROED"

same "the clean-up is set for the end of the script only (it ran twice after Ctrl-C)" "$(grep -c '^trap cleanup EXIT$' "$BUILD")" "1"
isnt "the clean-up is not also set for INT and TERM" grep -q '^trap cleanup EXIT INT' "$BUILD"

# ---- versions from <stream>/package.json
version_of() { # version_of <content of package.json> <package>
  # a copy of the script in a folder of its own: the script reads the version files next to itself
  mkdir -p "$W/v/stable" "$W/v/scripts"
  cp "$BUILD" "$W/v/build-debian-image.sh"
  cp "$REPO/scripts/lib.sh" "$W/v/scripts/"
  printf '%s\n' "$1" > "$W/v/stable/package.json"
  # shellcheck disable=SC1091  # the copy made above
  ( source "$W/v/build-debian-image.sh"; trap - EXIT INT TERM; set +e; pinned_version stable "$2" ) 2> "$W/version.err"
}
same "an exact version is used" "$(version_of '{"dependencies":{"@homebridge/homebridge-apt-pkg":"2.0.26"}}' '@homebridge/homebridge-apt-pkg')" "2.0.26"
same "a pre-release version is used" "$(version_of '{"dependencies":{"@homebridge/homebridge-apt-pkg":"2.1.0-beta.4"}}' '@homebridge/homebridge-apt-pkg')" "2.1.0-beta.4"
same "a leading ^ is dropped" "$(version_of '{"dependencies":{"ffmpeg-for-homebridge":"^2.2.2"}}' 'ffmpeg-for-homebridge')" "2.2.2"
for bad in '{"dependencies":{}}' '{"dependencies":{"ffmpeg-for-homebridge":null}}' '{"dependencies":{"ffmpeg-for-homebridge":"latest"}}' '{"dependencies":{"ffmpeg-for-homebridge":"*"}}' '{"dependencies":{"ffmpeg-for-homebridge":">=2.0.0"}}' '{"dependencies":{"ffmpeg-for-homebridge":"2.2.2; reboot"}}'; do
  version_of "$bad" ffmpeg-for-homebridge > /dev/null
  same "no exact version ($bad): the build stops" "$?" "1"
done
has "the message names the file and the package" "$W/version.err" "stable/package.json has no exact version for ffmpeg-for-homebridge"
for stream in stable beta alpha; do
  is "the version file of $stream has exact versions today" bash -c "source '$BUILD'; trap - EXIT; pinned_version $stream '@homebridge/homebridge-apt-pkg' && pinned_version $stream ffmpeg-for-homebridge"
done

# ---- small things that only showed up in special cases
hasnt "the 'be quiet' text is no longer passed to commands as arguments" "$BUILD" 'APT_REDIRECT'
hasnt "the build machine's packages are not installed from inside the build" "$BUILD" "apt-get install -y -qq zstd"
has "zstd is in the build machine's package list" "$REPO/scripts/install-build-deps.sh" "sudo psmisc jq gzip zstd"
has "the script moves to its own folder, so it works from anywhere" "$BUILD" 'cd "${SCRIPT_DIR}"'

# ---- the base setup: a package list that does not install must stop the build and say why
fake apt-get 'case "$*" in *hyperv-daemons*) echo "E: Unable to locate package hyperv-daemons"; exit 100 ;; esac; exit 0'
base_setup arm64
isnt "a VM helper package that is missing stops the build" test "$BASE_SETUP_CODE" -eq 0
has "the error of the failed install is shown" "$W/base-setup.log" "Unable to locate package hyperv-daemons"
rm -f "$W/bin/apt-get"

finish

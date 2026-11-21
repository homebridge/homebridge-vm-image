#!/usr/bin/env bash
# shellcheck disable=SC2016  # single quotes are meant: the text is looked for as it is
# The image must know the release it belongs to: the release tag that the release workflow
# passes in must end up in /etc/hb-release and in the VM settings.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

BUILD="$REPO/build-debian-image.sh"

# the function as it is in the build script
error() { echo "ERROR: $*" >&2; }
eval "$(sed -n '/^image_version() {$/,/^}$/p' "$BUILD")"

same "a stable release tag is used as it is" "$(image_version 2026-11-21 stable amd64)" "2026-11-21"
same "a beta release tag is used as it is" "$(image_version beta-2026-11-21 beta arm64)" "beta-2026-11-21"
is "a local build with no tag gets the date, the stream and the CPU type" grep -qE '^[0-9]{8}-alpha-arm64$' <<< "$(image_version '' alpha arm64)"
isnt "a text with a space is refused" image_version '2026-11-21 x' stable amd64
isnt "a text with shell characters is refused" image_version '2026;reboot' stable amd64
isnt "a text with a quote is refused" image_version "2026'" stable amd64

has "the build reads the release tag from its third argument" "$BUILD" 'local RELEASE_TAG="${3:-${BUILD_VERSION:-}}"'
has "the build uses it as the version of the image" "$BUILD" 'BUILD_VERSION="$(image_version "$RELEASE_TAG" "$RELEASE_STREAM" "$ARCH")"'

STAGE2="$REPO/.github/workflows/release-stage-2_build_and_push_images.yml"
has "the release workflow passes the tag to the build" "$STAGE2" './build-debian-image.sh "$ARCH" "$RELEASE_STREAM" "$HOMEBRIDGE_VM_IMAGE_VERSION"'
has "the boot test checks that the image holds the tag" "$STAGE2" '"$ARCH" "$HOMEBRIDGE_VM_IMAGE_VERSION" "$APT_VERSION"'

BUILD_VERSION=beta-2026-11-21 run_stage 01-homebridge 00-run.sh
same "the Homebridge stage writes the version to /etc/hb-release" "$(cat "$W/root/etc/hb-release")" "beta-2026-11-21"
has "and to the VM settings" "$W/chroot-script" "export HOMEBRIDGE_VM_IMAGE_VERSION=beta-2026-11-21"

finish

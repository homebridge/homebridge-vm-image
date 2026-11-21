#!/usr/bin/env bash
# The build workflow must name a fixed runner image and must not ask for packages that are
# gone. (A new "ubuntu-latest" without the qemu-user-static package stopped every build in
# November 2026.)
# shellcheck disable=SC2016  # single quotes are meant: the text is looked for as it is
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

STAGE2="$REPO/.github/workflows/release-stage-2_build_and_push_images.yml"

DEPS="$REPO/scripts/install-build-deps.sh"
CI="$REPO/.github/workflows/ci.yml"

hasnt "the build does not install qemu-user-static (nothing is emulated)" "$STAGE2" "qemu-user-static"
hasnt "the package list does not name qemu-user-static" "$DEPS" "qemu-user-static"
has "the release build installs its packages from the one list" "$STAGE2" './scripts/install-build-deps.sh "$ARCH"'
has "pull requests install the same list" "$CI" './scripts/install-build-deps.sh "$ARCH"'
has "the local Docker build installs the same list" "$REPO/scripts/Dockerfile" 'install-build-deps.sh "$ARCH"'
same "pull requests try the list on the runner images of the release build" \
  "$(sed -n '/^  build-host-packages:/,$p' "$CI" | sed -n 's/^ *runs-on: \(ubuntu.*\)$/\1/p' | sort | tr '\n' ' ')" "ubuntu-24.04 ubuntu-24.04-arm "
# the two build runners, as named in the matrix of the build job
same "the image is built on fixed runner images" \
  "$(grep -A1 -E '^ +- arch: (arm64|amd64)$' "$STAGE2" | sed -n 's/^ *runs-on: //p' | tr '\n' ' ')" "ubuntu-24.04-arm ubuntu-24.04 "

finish

#!/usr/bin/env bash
# The build workflow must name a fixed runner image and must not ask for packages that are
# gone. (A new "ubuntu-latest" without the qemu-user-static package stopped every build in
# November 2026.)
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

STAGE2="$REPO/.github/workflows/release-stage-2_build_and_push_images.yml"

hasnt "the build does not install qemu-user-static (nothing is emulated)" "$STAGE2" "qemu-user-static"
# the two build runners, as named in the matrix of the build job
same "the image is built on fixed runner images" \
  "$(grep -A1 -E '^ +- arch: (arm64|amd64)$' "$STAGE2" | sed -n 's/^ *runs-on: //p' | tr '\n' ' ')" "ubuntu-24.04-arm ubuntu-24.04 "

finish

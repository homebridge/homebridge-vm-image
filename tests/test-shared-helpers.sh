#!/usr/bin/env bash
# shellcheck disable=SC2016  # single quotes are meant: the text is looked for as it is
# The build and packaging scripts share one set of helpers and one order of arguments.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

LIB="$REPO/scripts/lib.sh"
USERS=(build-debian-image.sh scripts/convert-img-to-virtual-disk.sh scripts/create-release-body.sh scripts/local-build-in-docker.sh scripts/package-for-utm.sh scripts/package-for-virtual-box.sh)

for script in "${USERS[@]}"; do
  is "$script loads the shared helpers" grep -qE '^source "\$\{(SCRIPT_DIR|REPO_ROOT)\}/scripts/lib\.sh"$' "$REPO/$script"
  isnt "$script has no copy of the log helper" grep -qE '^log\(\) \{' "$REPO/$script"
  is "$script is valid bash" bash -n "$REPO/$script"
done
# (chroot-base-setup.sh runs inside the new system, where the repo is not there: it keeps its own)
same "the helpers are written down once for the scripts that run on the build machine" \
  "$(grep -lE '^log\(\) \{' "$REPO"/build-debian-image.sh "$REPO"/scripts/*.sh | sed "s#^$REPO/##" | tr '\n' ' ')" "scripts/chroot-base-setup.sh scripts/lib.sh "

# the helpers themselves
out="$(bash -c "source '$LIB'; log one; warn two; error three; info four" 2>&1 >/dev/null | sed 's/\x1b\[[0-9;]*m//g' | sed -E 's/^\[[0-9:]+\] ?//' | tr '\n' ';')"
same "the helpers write to the error output" "$out" "one;WARN: two;ERROR: three;INFO: four;"
same "in a GitHub run a group is a folded section" "$(GITHUB_ACTIONS=true bash -c "source '$LIB'; group_log Title; group_end")" "$(printf '::group::Title\n::endgroup::')"
fake uname 'echo aarch64'
same "an ARM machine is arm64" "$(PATH="$W/bin:$PATH" bash -c "source '$LIB'; detect_arch")" "arm64"
fake uname 'echo x86_64'
same "an Intel/AMD machine is amd64" "$(PATH="$W/bin:$PATH" bash -c "source '$LIB'; detect_arch")" "amd64"

# one order of arguments: the CPU type first, then the stream
for script in scripts/package-for-utm.sh scripts/package-for-virtual-box.sh scripts/local-build-in-docker.sh; do
  has "$script takes the CPU type first" "$REPO/$script" 'ARCH="${1:-$(detect_arch)}"'
  has "$script takes the stream second" "$REPO/$script" 'RELEASE_STREAM="${2:-stable}"'
done
has "the UTM workflow passes them in that order" "$REPO/.github/workflows/release-stage-4_package-for-utm.yml" './scripts/package-for-utm.sh "$ARCH" "$RELEASE_STREAM"'
has "the VirtualBox workflow passes them in that order" "$REPO/.github/workflows/release-stage-4_package-for-virtualbox.yml" './scripts/package-for-virtual-box.sh "$ARCH" "$RELEASE_STREAM"'

# a stream where the CPU type belongs is refused (so the old order fails loudly, not silently)
( cd "$W" && bash "$REPO/scripts/package-for-utm.sh" stable arm64 ) > "$W/utm.log" 2>&1
same "the UTM script refuses the old order of arguments" "$?" "1"
has "and says what is wrong" "$W/utm.log" "Unsupported architecture: stable"

finish

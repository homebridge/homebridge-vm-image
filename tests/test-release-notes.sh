#!/usr/bin/env bash
# shellcheck disable=SC2016  # single quotes are meant: that text must reach the fake command as it is
# The release notes: which release they compare with, and which commits they list.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

# a small repo with the script, the header, three streams, tags and commits
G="$W/repo"
mkdir -p "$G/scripts" "$G/assets" "$G/stable" "$G/beta" "$G/alpha" "$G/output"
cp "$REPO/scripts/create-release-body.sh" "$REPO/scripts/lib.sh" "$G/scripts/"
cp "$REPO/assets/release-body-header.md" "$G/assets/"
git() { command git -C "$G" -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }
pkg() { echo "{\"dependencies\":{\"@homebridge/homebridge-apt-pkg\":\"$2\",\"ffmpeg-for-homebridge\":\"$3\"}}" > "$G/$1/package.json"; }
commit() { git add -A > /dev/null && git commit -q -m "$1"; }
manifest() { # manifest <file> <apt version>
  printf 'Homebridge VM Package Manifest\n\nRelease Version: x\n\n| Package | Version |\n|:-------:|:-------:|\n| Debian | trixie |\n| NodeJS | v24.1.0 |\n| Homebridge APT Package | %s |\n' "$2" > "$1"
}

git init -q -b latest
printf 'output/\n.previous/\n' > "$G/.gitignore"
pkg stable 2.0.23 2.2.2; pkg beta 2.1.0-beta.1 2.2.2; pkg alpha 2.1.0-alpha.1 2.2.2
commit "first"
git tag 2026-10-29
git tag beta-2026-11-07
git tag v0.0.1
pkg stable 2.0.24 2.2.2; commit "STABLE: Update stable dependencies in stable"
git tag 2026-11-01
pkg beta 2.1.0-beta.2 2.2.2; commit "BETA: Update beta dependencies in beta"
pkg alpha 2.1.0-alpha.2 2.2.2; commit "ALPHA: Update alpha dependencies in alpha"
echo "change" > "$G/assets/shared.txt"; commit "fix: a change to a shared file"
pkg stable 2.0.26 2.2.2; commit "STABLE: Update stable dependencies in stable again"

# A fake gh: "release download <tag> ... --dir <dir>" writes the manifest of that release there.
cat > "$W/bin/gh" <<FAKE
#!/bin/sh
echo "gh \$*" >> "$W/calls.log"
tag="\$3"; dir=""
while [ \$# -gt 0 ]; do [ "\$1" = "--dir" ] && dir="\$2"; shift; done
[ -f "$W/release-\$tag.manifest" ] || exit 1
cp "$W/release-\$tag.manifest" "\$dir/homebridge-vm-image-stable-amd64.manifest"
FAKE
chmod +x "$W/bin/gh"
manifest "$W/release-2026-11-01.manifest" 2.0.24
manifest "$W/release-2026-10-29.manifest" 2.0.23
manifest "$G/output/homebridge-vm-image-stable-amd64.manifest" 2.0.26

notes() { rm -f "${W:?}/calls.log"; ( PATH="$W/bin:$PATH" "$@" "$G/scripts/create-release-body.sh" "${STREAM:-stable}" ) > "$W/notes.log" 2>&1; code=$?; }
BODY="$G/output/release-body.md"

notes env
same "the script ends with code 0" "$code" "0"
has "stable compares with the newest stable release" "$BODY" "## Changes Since Previous Release (2026-11-01):"
has "the version change is listed" "$BODY" "* **@homebridge/homebridge-apt-pkg**: Updated from 2.0.24 to 2.0.26"
has "the heading for version changes is about packages" "$BODY" "## Package Version Changes"
hasnt "the Docker heading is gone" "$BODY" "Docker Build Instruction Changes"
has "the manifest change is shown, old line then new line" "$BODY" "$(printf -- '-| Homebridge APT Package | 2.0.24 |\n+| Homebridge APT Package | 2.0.26 |')"
has "a commit to a shared file is listed" "$BODY" "fix: a change to a shared file"
has "the stream's own version commit is listed" "$BODY" "STABLE: Update stable dependencies in stable again"
hasnt "the beta bot commit is not in the stable notes" "$BODY" "BETA: Update beta dependencies"
hasnt "the alpha bot commit is not in the stable notes" "$BODY" "ALPHA: Update alpha dependencies"

# a second build on the same day: the tag of this release exists already
git tag 2026-11-21
manifest "$W/release-2026-11-21.manifest" 2.0.26
notes env CURRENT_TAG=2026-11-21
has "a second build on the same day still compares with the release before it" "$BODY" "## Changes Since Previous Release (2026-11-01):"
hasnt "and not with itself" "$BODY" "Previous Release (2026-11-21)"
git tag -d 2026-11-21 > /dev/null

STREAM=beta notes env
has "beta compares with the newest beta release" "$W/calls.log" "gh release download beta-2026-11-07"
has "the beta bot commit is in the beta notes" "$BODY" "BETA: Update beta dependencies in beta"
hasnt "the stable bot commit is not in the beta notes" "$BODY" "STABLE: Update stable dependencies"

# alpha has no release yet: nothing may be downloaded (an empty tag would take any release)
STREAM=alpha notes env
same "no previous release: gh is not asked to download anything" "$(calls | grep -c 'release download')" "0"
has "no previous release: the notes say so" "$BODY" "Previous release manifest not available for comparison."
has "no previous release: recent commits are listed" "$BODY" "### Recent Changes"

# a long list of changes is cut, and the notes say so
{ manifest /dev/stdout 2.0.24; for n in $(seq 30); do echo "| pkg$n | 1.0 |"; done; } > "$W/release-2026-11-01.manifest"
{ manifest /dev/stdout 2.0.26; for n in $(seq 30); do echo "| pkg$n | 2.0 |"; done; } > "$G/output/homebridge-vm-image-stable-amd64.manifest"
notes env
has "a cut list says how many lines are missing" "$BODY" "more changed lines are not shown"

STREAM=nightly notes env
isnt "a stream it does not know is refused" test "$code" -eq 0

same "no fixed file name in /tmp is used" "$(grep -c '/tmp/' "$REPO/scripts/create-release-body.sh")" "0"
has "Stage 3 passes the tag of the release being made" "$REPO/.github/workflows/release-stage-3_package_release.yml" 'CURRENT_TAG="$TAG" ./scripts/create-release-body.sh "$RELEASE_STREAM"'

finish

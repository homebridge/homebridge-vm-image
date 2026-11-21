#!/usr/bin/env bash
# Prints "true" when the versions in <stream>/package.json are not the ones in the newest
# release of that stream, else "false".
#
# Usage: unreleased-versions.sh <stable|beta|alpha>
#
# Why: the dependency bot writes new versions to the branch BEFORE the image is built. If that
# build fails, the bot finds nothing new on the next day, and the release for those versions
# would never be made. This check lets the daily run see that and build again.
#
# How: every release holds a file homebridge-vm-image-<stream>-<arch>.manifest with the versions
# that were built. The two lines for the Homebridge apt package and for ffmpeg are compared with
# package.json.
#
# Needs the gh command and GH_TOKEN (read access is enough). Exit code 1: the release list or
# the manifest could not be read. That is an error, not a "false".
set -euo pipefail

STREAM="${1:?usage: unreleased-versions.sh <stable|beta|alpha>}"

case "$STREAM" in
  stable) TAG_FORM='^[0-9]{4}-[0-9]{2}-[0-9]{2}$' ;;
  beta | alpha) TAG_FORM="^${STREAM}-[0-9]{4}-[0-9]{2}-[0-9]{2}\$" ;;
  *) echo "unreleased-versions.sh: not a stream name: ${STREAM}" >&2; exit 1 ;;
esac

cd "$(dirname "${BASH_SOURCE[0]}")/.."

WANT_APT="$(jq -r '.dependencies["@homebridge/homebridge-apt-pkg"] // empty' "${STREAM}/package.json" | sed 's/^\^//')"
WANT_FFMPEG="$(jq -r '.dependencies["ffmpeg-for-homebridge"] // empty' "${STREAM}/package.json" | sed 's/^\^//')"
if [[ -z "$WANT_APT" || -z "$WANT_FFMPEG" ]]; then
  echo "unreleased-versions.sh: ${STREAM}/package.json does not name both versions" >&2
  exit 1
fi

# the newest release of this stream that is not a draft (the tags sort by date)
TAGS="$(gh release list --limit 100 --json tagName,isDraft --jq '.[] | select(.isDraft | not) | .tagName')"
NEWEST_TAG="$(grep -E "$TAG_FORM" <<< "$TAGS" | sort | tail -n 1 || true)"

if [[ -z "$NEWEST_TAG" ]]; then
  echo "unreleased-versions.sh: no ${STREAM} release found" >&2
  echo "true"
  exit 0
fi

# one manifest is enough: both CPU types are built from the same package.json
MANIFEST="$(gh release download "$NEWEST_TAG" --pattern "homebridge-vm-image-${STREAM}-*.manifest" --output - 2> /dev/null | tr -d '\r' || true)"

if [[ -z "$MANIFEST" ]]; then
  # a release with no manifest is one that was never finished
  echo "unreleased-versions.sh: release ${NEWEST_TAG} has no manifest" >&2
  echo "true"
  exit 0
fi

# the value of a table line like "| Homebridge APT Package | 2.0.26 |"
value_of() {
  awk -F'|' -v name="$1" '{ key = $2; gsub(/^ +| +$/, "", key); if (key == name) { value = $3; gsub(/^ +| +$/, "", value); print value; exit } }' <<< "$MANIFEST"
}

HAVE_APT="$(value_of "Homebridge APT Package")"
HAVE_FFMPEG="$(value_of "ffmpeg for homebridge")"

if [[ "$HAVE_APT" == "$WANT_APT" && "${HAVE_FFMPEG#v}" == "$WANT_FFMPEG" ]]; then
  echo "false"
else
  echo "unreleased-versions.sh: release ${NEWEST_TAG} has apt package '${HAVE_APT}' and ffmpeg '${HAVE_FFMPEG}'; the branch has '${WANT_APT}' and '${WANT_FFMPEG}'" >&2
  echo "true"
fi

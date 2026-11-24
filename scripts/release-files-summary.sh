#!/bin/bash
# Prints a Markdown summary of a GitHub release's files, for $GITHUB_STEP_SUMMARY.
#
# Usage: release-files-summary.sh <tag> <heading> [file name pattern]
#   pattern: an extended regex on the file name (default: every file)
#
# Needs gh (with GH_TOKEN, read access is enough) and jq. Never fails the job: when the release
# can not be read, it says so in the summary instead.

set -uo pipefail

TAG="${1:?usage: release-files-summary.sh <tag> <heading> [pattern]}"
HEADING="${2:?usage: release-files-summary.sh <tag> <heading> [pattern]}"
PATTERN="${3:-.}"

echo "### ${HEADING}"
echo

if ! RELEASE_JSON="$(gh release view "$TAG" --json url,assets 2> /dev/null)"; then
  echo "Release \`${TAG}\` could not be read."
  exit 0
fi

echo "Release: [\`${TAG}\`]($(jq -r '.url' <<< "$RELEASE_JSON"))"
echo

ROWS="$(jq -r --arg p "$PATTERN" '
  .assets[] | select(.name | test($p))
  | "| `\(.name)` | \(if .size >= 1073741824 then "\(.size / 1073741824 * 10 | floor / 10) GB" else "\(.size / 1048576 | floor) MB" end) |"
' <<< "$RELEASE_JSON")"

if [ -z "$ROWS" ]; then
  echo "No files matching \`${PATTERN}\` in the release."
  exit 0
fi

echo "| File | Size |"
echo "|---|---|"
echo "$ROWS"

#!/usr/bin/env bash
# Picks the releases of one stream that are old enough to delete.
#
# Usage: old-releases.sh <stable|beta|alpha> <number to keep>
# Reads release tags on standard input, one per line. Prints the tags to delete, one per line.
#
# Only tags in the exact form of the stream are looked at:
#   stable: YYYY-MM-DD      beta: beta-YYYY-MM-DD      alpha: alpha-YYYY-MM-DD
# The newest <number to keep> of them stay. Any other tag is never printed.
set -euo pipefail

STREAM="${1:?usage: old-releases.sh <stable|beta|alpha> <number to keep>}"
KEEP="${2:?usage: old-releases.sh <stable|beta|alpha> <number to keep>}"

case "$STREAM" in
  stable) TAG_FORM='^[0-9]{4}-[0-9]{2}-[0-9]{2}$' ;;
  beta | alpha) TAG_FORM="^${STREAM}-[0-9]{4}-[0-9]{2}-[0-9]{2}\$" ;;
  *) echo "old-releases.sh: the stream must be stable, beta or alpha" >&2; exit 1 ;;
esac

if ! [[ "$KEEP" =~ ^[1-9][0-9]*$ ]]; then
  echo "old-releases.sh: the number to keep must be a whole number above 0" >&2
  exit 1
fi

# the tags sort by date; newest first, then everything after the first <KEEP> lines
{ grep -E "$TAG_FORM" || true; } | sort -r | tail -n "+$((KEEP + 1))"

#!/usr/bin/env bash
# Runs shellcheck on every shell script in this repo.
#
# Usage: scripts/lint.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# every tracked file that starts with a shell "#!" line, plus every *.sh file
mapfile -t FILES < <(
  git ls-files | while read -r file; do
    [ -f "$file" ] || continue
    case "$file" in
      *.sh) echo "$file" ;;
      *) head -c 64 "$file" | head -n 1 | grep -qE '^#! ?/(usr/)?bin/(env )?(ba|da)?sh' && echo "$file" ;;
    esac
  done | sort -u
)

echo "shellcheck: ${#FILES[@]} files"
shellcheck --version | sed -n 2p
shellcheck -x "${FILES[@]}"
echo "shellcheck: no notes"

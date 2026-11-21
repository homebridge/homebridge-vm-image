#!/usr/bin/env bash
# shellcheck disable=SC2016  # single quotes are meant: that text must reach the fake command as it is
# The daily run must see that the versions on the branch were never released (because the build
# for them failed), so that it builds again.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

# a copy of the script with its own package.json files
mkdir -p "$W/repo/scripts" "$W/repo/stable" "$W/repo/beta"
cp "$REPO/scripts/unreleased-versions.sh" "$W/repo/scripts/"
echo '{"dependencies":{"@homebridge/homebridge-apt-pkg":"2.0.26","ffmpeg-for-homebridge":"2.2.2"}}' > "$W/repo/stable/package.json"
echo '{"dependencies":{"@homebridge/homebridge-apt-pkg":"2.1.0-beta.4","ffmpeg-for-homebridge":"2.2.2"}}' > "$W/repo/beta/package.json"

# A fake gh. "release list" prints $W/tags. "release download <tag>" prints $W/manifest-<tag>.
cat > "$W/bin/gh" <<FAKE
#!/bin/sh
echo "gh \$*" >> "$W/calls.log"
[ -e "$W/gh-fails" ] && exit 1
case "\$1 \$2" in
  "release list") cat "$W/tags" ;;
  "release download") [ -f "$W/manifest-\$3" ] && cat "$W/manifest-\$3" || exit 1 ;;
  *) exit 1 ;;
esac
FAKE
chmod +x "$W/bin/gh"

manifest() { # manifest <tag> <apt version> <ffmpeg version>
  printf 'Homebridge VM Package Manifest\n\nRelease Version: %s\n\n| Package | Version |\n|:-------:|:-------:|\n| Debian | trixie |\n| Homebridge | 2.0.4 |\n| ffmpeg for homebridge | %s |\n| Homebridge APT Package | %s |\n' "$1" "$3" "$2" > "$W/manifest-$1"
}
check() { PATH="$W/bin:$PATH" "$W/repo/scripts/unreleased-versions.sh" "$1" 2> "$W/err"; }

printf '%s\n' beta-2026-11-07 2026-11-01 alpha-2026-11-06 2026-10-29 > "$W/tags"
manifest 2026-11-01 2.0.23 v2.2.2
manifest 2026-10-29 2.0.26 v2.2.2
same "true when the newest stable release has an older apt package (the November 2026 case)" "$(check stable)" "true"
has "it says which versions differ" "$W/err" "release 2026-11-01 has apt package '2.0.23'"

manifest 2026-11-01 2.0.26 v2.2.2
same "false when the newest release has the versions of the branch" "$(check stable)" "false"

manifest 2026-11-01 2.0.26 v2.2.1
same "true when only ffmpeg differs" "$(check stable)" "true"

manifest beta-2026-11-07 2.1.0-beta.4 v2.2.2
same "beta is compared with the newest beta release, not with a stable one" "$(check beta)" "false"
manifest beta-2026-11-07 2.1.0-beta.3 v2.2.2
same "true for an older beta" "$(check beta)" "true"

rm -f "$W/manifest-2026-11-01"
same "true when the newest release has no manifest (it was never finished)" "$(check stable)" "true"

printf '%s\n' beta-2026-11-07 > "$W/tags"
same "true when the stream has no release at all" "$(check stable)" "true"

touch "$W/gh-fails"
check stable > /dev/null
same "an unreadable release list is an error, not an answer" "$?" "1"
rm -f "$W/gh-fails"

isnt "a stream name it does not know is refused" check 'stable; echo x'

STAGE1="$REPO/.github/workflows/release-stage-1_update_dependencies.yml"
has "Stage 1 asks the script" "$STAGE1" './scripts/unreleased-versions.sh "$STREAM"'
has "Stage 1 builds when the versions were never released" "$STAGE1" 'elif [[ "$UNRELEASED" == "true" ]]; then'

finish

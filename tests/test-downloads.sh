#!/usr/bin/env bash
# shellcheck disable=SC2016  # single quotes are meant: that text must reach the script under test as it is
# What the build downloads and then trusts: the ffmpeg archive (unpacked into / as root) and the
# key of the Homebridge package repo. Both must match a known value, or the build stops.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

GOOD_SHA="$(printf 'the real archive\n' | sha256sum | cut -d' ' -f1)"

# inside [no-ffmpeg]: runs the lines a stage wrote for inside the image, with stand-ins for
# curl, tar, gpg, apt-get and (unless $1 is "no-ffmpeg") ffmpeg
inside() {
  rm -rf "${W:?}/calls.log" "${W:?}/bin" "${W:?}/in"
  mkdir -p "$W/bin" "$W/in"
  fake uname 'exit 0'
  # curl writes the "download" to the file after -o
  fake curl "while [ \$# -gt 1 ]; do [ \"\$1\" = \"-o\" ] && cat \"$W/download\" > \"\$2\"; shift; done"
  fake tar 'exit 0'
  fake apt-get 'exit 0'
  fake systemctl 'exit 0'
  fake visudo 'exit 0'
  fake gpg "case \"\$*\" in *--show-keys*) echo 'pub:-:4096:1:DF5B0FE88C8F5D92:1:::-:::scESC::::::23::0:'; echo \"fpr:::::::::\$(cat '$W/key-fingerprint'):\" ;; *) cat ;; esac"
  [ "${1:-}" = "no-ffmpeg" ] || fake ffmpeg 'echo "ffmpeg version 8.0"'
  # only the stand-ins and the basic tools are on the PATH, so a real ffmpeg on this machine is not found
  ( cd "$W/in" && sed -E "s#(^|[[:space:]=\"'>])/(etc|usr|opt|root|var)/#\1$W/in/\2/#g" "$W/chroot-script" > "$W/in/script" \
    && mkdir -p usr/share/keyrings etc/apt/sources.list.d etc/systemd/system usr/local/lib/homebridge-vm root var/lib \
    && : > etc/nsswitch.conf && PATH="$W/bin:/usr/bin:/bin" bash -e "$W/in/script" ) > "$W/inside.log" 2>&1
}

# ---- ffmpeg
printf 'the real archive\n' > "$W/download"

FFMPEG_SHA256="$GOOD_SHA" run_stage 05-ffmpeg 01-run.sh
same "the ffmpeg stage runs" "$STAGE_CODE" "0"
inside
same "a download with the expected checksum is installed" "$?" "0"
has "the arm64 file of the given release is downloaded" "$W/calls.log" "https://github.com/homebridge/ffmpeg-for-homebridge/releases/download/v2.2.2/ffmpeg-alpine-aarch64.tar.gz"
has "the download is unpacked into /" "$W/calls.log" "-C / --no-same-owner"
has "ffmpeg is started once as a test" "$W/calls.log" "ffmpeg -version"

printf 'another archive\n' > "$W/download"
inside
isnt "a download with another checksum stops the build" test "$?" -eq 0
isnt "a download with another checksum is not unpacked" grep -q '^tar ' "$W/calls.log"
printf 'the real archive\n' > "$W/download"

inside no-ffmpeg
isnt "the build stops when ffmpeg does not run after the install" test "$?" -eq 0

ARCH=amd64 FFMPEG_SHA256="$GOOD_SHA" run_stage 05-ffmpeg 01-run.sh
inside
has "the x86_64 file is downloaded for an amd64 image" "$W/calls.log" "ffmpeg-alpine-x86_64.tar.gz"

FFMPEG_SHA256='' run_stage 05-ffmpeg 01-run.sh
isnt "the ffmpeg stage stops when no checksum is passed in" test "$STAGE_CODE" -eq 0
ARCH=riscv64 FFMPEG_SHA256="$GOOD_SHA" run_stage 05-ffmpeg 01-run.sh
isnt "the ffmpeg stage stops on an architecture it does not know" test "$STAGE_CODE" -eq 0

# ---- scripts/ffmpeg-checksum.sh with a stand-in for the GitHub API
CHECKSUM="$REPO/scripts/ffmpeg-checksum.sh"
rm -rf "${W:?}/bin" && mkdir -p "${W:?}/bin"
cat > "$W/api.json" <<JSON
{"assets": [
  {"name": "ffmpeg-alpine-aarch64.tar.gz", "digest": "sha256:$GOOD_SHA"},
  {"name": "ffmpeg-alpine-x86_64.tar.gz", "digest": null},
  {"name": "ffmpeg-alpine-arm32v7.tar.gz", "digest": "sha256:short"}
]}
JSON
fake curl "cat \"$W/api.json\""
same "the checksum helper prints the checksum of the asked file" "$(PATH="$W/bin:$PATH" "$CHECKSUM" v2.2.2 aarch64)" "$GOOD_SHA"
has "the checksum helper asks for the release with that tag" "$W/calls.log" "releases/tags/v2.2.2"
isnt "the checksum helper stops when GitHub has no checksum for the file" env PATH="$W/bin:$PATH" "$CHECKSUM" v2.2.2 x86_64
isnt "the checksum helper stops on an architecture it does not know" env PATH="$W/bin:$PATH" "$CHECKSUM" v2.2.2 arm32v7
isnt "the checksum helper stops on a tag with other characters" env PATH="$W/bin:$PATH" "$CHECKSUM" "v2.2.2/../x" aarch64
fake curl 'exit 22'
isnt "the checksum helper stops when GitHub can not be reached" env PATH="$W/bin:$PATH" "$CHECKSUM" v2.2.2 aarch64

has "the build asks for the checksum and passes it to the stages" "$REPO/build-debian-image.sh" 'FFMPEG_SHA256="$("${SCRIPT_DIR}/scripts/ffmpeg-checksum.sh" "${FFMPEG_FOR_HOMEBRIDGE_VERSION}" "${FFMPEG_ARCH}")"'

# ---- the key of the Homebridge package repo
run_stage 01-homebridge 00-run.sh
same "the Homebridge stage runs" "$STAGE_CODE" "0"
echo "KEY DATA" > "$W/download"

echo "ACAA60814A7524504F07DE07DF5B0FE88C8F5D92" > "$W/key-fingerprint"
inside
same "the known key: the stage goes on" "$?" "0"
same "the known key is installed for apt" "$(cat "$W/in/usr/share/keyrings/homebridge.gpg")" "KEY DATA"
has "the Homebridge package is installed at the pinned version" "$W/calls.log" "apt-get install -y homebridge=2.0.26"

echo "0000000000000000000000000000000000000000" > "$W/key-fingerprint"
inside
isnt "another key: the build stops" test "$?" -eq 0
isnt "another key is not installed for apt" test -s "$W/in/usr/share/keyrings/homebridge.gpg"
same "another key: nothing is installed with it" "$(calls | grep -c '^apt-get')" "0"

finish

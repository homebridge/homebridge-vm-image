#!/bin/bash -e 

#
# Install ffmpeg
#

on_chroot << 'EOF'
uname -a

set -ex

case "$(uname -m)" in
  x86_64) FFMPEG_ARCH='x86_64' ;;
  armv7l) FFMPEG_ARCH='arm32v7' ;;
  aarch64) FFMPEG_ARCH='aarch64' ;;
  *) echo "unsupported architecture"; exit 1 ;;
esac

curl -Lfs "https://github.com/homebridge/ffmpeg-for-homebridge/releases/download/${FFMPEG_FOR_HOMEBRIDGE_VERSION}/ffmpeg-alpine-${FFMPEG_ARCH}.tar.gz" | tar xzf - -C / --no-same-owner
ffmpeg || exit 0
EOF
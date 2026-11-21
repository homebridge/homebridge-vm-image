#!/usr/bin/env bash
# shellcheck disable=SC2016  # single quotes are meant: the text is looked for, or passed on, as it is
# Every disk format must come out with the same virtual disk size (50 GB in a release).
# VHDX and VMDK used to stay at the 5 GB of the raw image.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

if ! command -v qemu-img > /dev/null; then
  fail "qemu-img is installed (package qemu-utils)"
  finish
fi

# the real script and the real qemu-img, on a small stand-in image and with a small target size
mkdir -p "$W/repo/scripts" "$W/repo/output"
cp "$REPO/scripts/convert-img-to-virtual-disk.sh" "$REPO/scripts/lib.sh" "$W/repo/scripts/"
truncate -s 8M "$W/repo/output/homebridge-vm-image-stable-arm64.img"
echo "data" | dd of="$W/repo/output/homebridge-vm-image-stable-arm64.img" conv=notrunc status=none

VDISK_SIZE=64M GITHUB_ACTIONS=false bash "$W/repo/scripts/convert-img-to-virtual-disk.sh" > "$W/convert.log" 2>&1
same "the convert script ends with code 0" "$?" "0"

WANT=$((64 * 1024 * 1024))
size_of() { qemu-img info --output=json "$1" | jq -r '."virtual-size"'; }
same "QCOW2 has the full disk size" "$(size_of "$W/repo/output/homebridge-vm-image-stable-arm64.qcow2")" "$WANT"
same "VHDX has the full disk size" "$(size_of "$W/repo/output/homebridge-vm-image-stable-arm64.vhdx")" "$WANT"
same "VMDK has the full disk size" "$(size_of "$W/repo/output/homebridge-vm-image-stable-arm64.vmdk")" "$WANT"
is "the compressed VHDX is there" test -s "$W/repo/output/homebridge-vm-image-stable-arm64.vhdx.gz"
is "the compressed VMDK is there" test -s "$W/repo/output/homebridge-vm-image-stable-arm64.vmdk.gz"
same "the grown work copy is removed" "$(find "$W/repo/output" -name '*.grown.raw' | wc -l | tr -d ' ')" "0"
for format in vhdx vmdk; do
  qemu-img convert -O raw "$W/repo/output/homebridge-vm-image-stable-arm64.$format" "$W/back.raw"
  same "the data of the image is still at the start of the ${format} disk" "$(head -c 4 "$W/back.raw")" "data"
done

same "a release uses 50 GB" "$(sed -n 's/^VDISK_SIZE="${VDISK_SIZE:-\(.*\)}"$/\1/p' "$REPO/scripts/convert-img-to-virtual-disk.sh")" "50G"

HYPERV="$REPO/.github/workflows/release-stage-4_package-for-hyperv.yml"
has "the Hyper-V package uses 50 GB too" "$HYPERV" "VDISK_SIZE: 50G"
has "the Hyper-V disk is grown before the VM is made" "$HYPERV" 'resize -f vhdx $vhdxPath $env:VDISK_SIZE'

finish

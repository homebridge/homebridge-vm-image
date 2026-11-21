#!/usr/bin/env bash
# Boot test: starts a built image as a real virtual machine and checks it from the inside.
# The release workflow runs it on every image BEFORE anything is published. A failed test stops
# the release.
#
# Usage: boot-test.sh <image file (.img)> <arm64|amd64> [expected /etc/hb-release] [expected apt package version]
#
# What it does:
#   - The image file is not changed. The VM runs on a throw-away copy-on-write disk on top of it.
#     That disk is 3 GB larger than the image, to see that the system grows into a larger disk.
#   - The VM starts the same way a user's VM does: UEFI firmware, GRUB, kernel, systemd.
#   - The checks (scripts/boot-test-checks.sh) run inside the VM through the QEMU guest agent,
#     which the image installs. No account and no password are needed.
#   - The Homebridge UI is also fetched from outside the VM, through a forwarded port.
#
# Needs: qemu-system-arm or qemu-system-x86, the UEFI firmware (qemu-efi-aarch64 or ovmf),
# qemu-utils, python3 and curl. scripts/install-build-deps.sh installs them.
# With /dev/kvm the VM runs at full speed. Without it QEMU emulates the CPU, which is slower
# (about 2 to 5 minutes in all).
set -euo pipefail

IMAGE="${1:?usage: boot-test.sh <image file> <arm64|amd64> [expected release] [expected apt version]}"
ARCH="${2:?usage: boot-test.sh <image file> <arm64|amd64> [expected release] [expected apt version]}"
EXPECTED_RELEASE="${3:--}"
EXPECTED_APT_VERSION="${4:--}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GROW_GB=3
UI_PORT="${BOOT_TEST_PORT:-18581}"

[[ -f "$IMAGE" ]] || { echo "boot-test.sh: no such image file: $IMAGE" >&2; exit 1; }

# first_file <path...>: prints the first path that exists
first_file() {
  local path
  for path in "$@"; do
    [[ -f "$path" ]] && { echo "$path"; return 0; }
  done
  return 1
}

case "$ARCH" in
  arm64)
    QEMU=qemu-system-aarch64
    MACHINE=(-M virt)
    HOST_MATCH=aarch64
    FIRMWARE_CODE="$(first_file /usr/share/AAVMF/AAVMF_CODE.no-secboot.fd /usr/share/AAVMF/AAVMF_CODE.fd)" || true
    FIRMWARE_VARS="$(first_file /usr/share/AAVMF/AAVMF_VARS.fd)" || true
    ;;
  amd64)
    QEMU=qemu-system-x86_64
    MACHINE=(-M q35 -vga none)
    HOST_MATCH=x86_64
    FIRMWARE_CODE="$(first_file /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd)" || true
    FIRMWARE_VARS="$(first_file /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd)" || true
    ;;
  *) echo "boot-test.sh: the architecture must be arm64 or amd64" >&2; exit 1 ;;
esac

if [[ -z "${FIRMWARE_CODE:-}" || -z "${FIRMWARE_VARS:-}" ]]; then
  echo "boot-test.sh: the UEFI firmware files were not found (run scripts/install-build-deps.sh)" >&2
  exit 1
fi

WORK="$(mktemp -d)"
QEMU_PID=""
cleanup() {
  if [[ -n "$QEMU_PID" ]] && kill -0 "$QEMU_PID" 2> /dev/null; then
    kill "$QEMU_PID" 2> /dev/null || true
    wait "$QEMU_PID" 2> /dev/null || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

# full speed when the machine can run this CPU type itself, else emulation
if [[ "$(uname -m)" == "$HOST_MATCH" && -w /dev/kvm ]]; then
  ACCEL=(-accel kvm -cpu host)
  WAIT_VM=300
else
  ACCEL=(-accel tcg -cpu max)
  WAIT_VM=900
fi

IMAGE_BYTES="$(stat -c %s "$IMAGE")"
DISK_GB=$((IMAGE_BYTES / 1024 / 1024 / 1024 + GROW_GB))
qemu-img create -q -f qcow2 -F raw -b "$(realpath "$IMAGE")" "$WORK/disk.qcow2" "${DISK_GB}G"
cp "$FIRMWARE_VARS" "$WORK/vars.fd"

echo "boot-test: starting $(basename "$IMAGE") (${ARCH}, ${ACCEL[1]}, disk ${DISK_GB} GB)"

"$QEMU" "${MACHINE[@]}" "${ACCEL[@]}" -smp 2 -m 2048 -display none -no-reboot \
  -drive "if=pflash,format=raw,readonly=on,file=${FIRMWARE_CODE}" \
  -drive "if=pflash,format=raw,file=${WORK}/vars.fd" \
  -drive "if=virtio,format=qcow2,file=${WORK}/disk.qcow2" \
  -device virtio-gpu-pci \
  -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${UI_PORT}-:8581" -device virtio-net-pci,netdev=net0,romfile= \
  -device virtio-serial-pci \
  -chardev "socket,id=agent0,path=${WORK}/agent.sock,server=on,wait=off" \
  -device virtserialport,chardev=agent0,name=org.qemu.guest_agent.0 \
  -serial "file:${WORK}/console.log" \
  > "$WORK/qemu.log" 2>&1 &
QEMU_PID=$!

sleep 2
if ! kill -0 "$QEMU_PID" 2> /dev/null; then
  echo "boot-test: QEMU did not start" >&2
  cat "$WORK/qemu.log" >&2
  exit 1
fi

# The root file system must have grown into the larger disk by itself, with nobody at the
# console: the disk size less the small boot partition ("df" rounds up to whole GB).
MIN_ROOT_GB=$((DISK_GB - 1))

CODE=0
python3 "$SCRIPT_DIR/boot-test-guest.py" "$WORK/agent.sock" "$SCRIPT_DIR/boot-test-checks.sh" "$WAIT_VM" 900 \
  "$EXPECTED_RELEASE" "$EXPECTED_APT_VERSION" "$MIN_ROOT_GB" || CODE=$?

if [[ "$CODE" -eq 0 ]]; then
  # the same page from outside the VM: through the VM's network card and the forwarded port
  OUTSIDE="$(curl -s -o /dev/null --max-time 20 -w '%{http_code}' "http://127.0.0.1:${UI_PORT}/" || true)"
  if [[ "$OUTSIDE" == "200" ]]; then
    echo "ok    the Homebridge UI answers from outside the VM"
  else
    echo "FAIL  the Homebridge UI answers from outside the VM (http code: ${OUTSIDE:-none})"
    CODE=1
  fi
fi

if [[ "$CODE" -ne 0 ]]; then
  echo "boot-test: FAILED (code ${CODE}). The last lines of the VM's console:" >&2
  tail -n 60 "$WORK/console.log" 2> /dev/null | tr -d '\r' | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' >&2 || true
  cat "$WORK/qemu.log" >&2 || true
  exit 1
fi

echo "boot-test: passed"

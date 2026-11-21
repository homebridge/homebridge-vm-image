#!/usr/bin/env bash
# expandVirtualFilesystem grows the root file system into a larger virtual disk. It must name
# the right disk for every kind of disk name, and it must not report success after a failure.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

# expand_on <root partition> <parent disk name> <partition number>: runs the script with fake
# disk tools that answer for that layout. Sets $code; the output is in $W/expand.log.
expand_on() {
  rm -rf "${W:?}/root" "${W:?}/calls.log"
  mkdir -p "$W/root/var/log" "$W/root/sys/class/block/$(basename "$1")"
  [ -n "$3" ] && echo "$3" > "$W/root/sys/class/block/$(basename "$1")/partition"
  fake findmnt "case \"\$*\" in *SOURCE*) echo '$1' ;; *FSTYPE*) echo '${FS_TYPE:-ext4}' ;; esac"
  fake lsblk "echo '$2'"
  fake df 'echo "/dev/x 50G 2G 48G 4% /"'
  fake partx
  [ -x "$W/bin/growpart" ] || fake growpart 'echo "CHANGED: partition=2 start=526336 old: size=9959424 new: size=104331231"'
  [ -x "$W/bin/resize2fs" ] || fake resize2fs
  in_sandbox "$FILES/expandVirtualFilesystem" > "$W/expand"
  PATH="$W/bin:$PATH" bash "$W/expand" > "$W/expand.log" 2>&1
  code=$?
}
grow_call() { calls | sed -n 's/^growpart //p'; }

expand_on /dev/sda2 sda 2
same "sda2: grows partition 2 of /dev/sda" "$(grow_call)" "/dev/sda 2"
same "sda2: ends with code 0" "$code" "0"
has "sda2: then grows the file system" "$W/calls.log" "resize2fs /dev/sda2"

expand_on /dev/vda2 vda 2
same "vda2: grows partition 2 of /dev/vda" "$(grow_call)" "/dev/vda 2"

expand_on /dev/nvme0n1p2 nvme0n1 2
same "nvme0n1p2: grows partition 2 of /dev/nvme0n1 (not of /dev/nvme0n1p)" "$(grow_call)" "/dev/nvme0n1 2"
has "nvme0n1p2: then grows the file system" "$W/calls.log" "resize2fs /dev/nvme0n1p2"

expand_on /dev/mmcblk0p2 mmcblk0 2
same "mmcblk0p2: grows partition 2 of /dev/mmcblk0" "$(grow_call)" "/dev/mmcblk0 2"

expand_on /dev/xvda12 xvda 12
same "a partition number with two digits is kept whole" "$(grow_call)" "/dev/xvda 12"

fake growpart 'echo "NOCHANGE: partition 2 is size 104331231. it cannot be grown"; exit 1'
expand_on /dev/sda2 sda 2
same "nothing to grow: ends with code 0" "$code" "0"
has "nothing to grow: says so" "$W/expand.log" "already at maximum size"
hasnt "nothing to grow: does not claim it grew the partition" "$W/expand.log" "Partition expanded successfully"
has "nothing to grow: the file system is still checked" "$W/calls.log" "resize2fs /dev/sda2"

fake growpart 'echo "FAILED: partition table could not be read" >&2; exit 2'
expand_on /dev/sda2 sda 2
same "growpart fails: ends with code 1" "$code" "1"
hasnt "growpart fails: does not say the partition was expanded" "$W/expand.log" "Partition expanded successfully"
hasnt "growpart fails: does not say the expansion is complete" "$W/expand.log" "expansion complete"
same "growpart fails: the file system is not touched" "$(calls | grep -c '^resize2fs')" "0"
rm -f "$W/bin/growpart"

fake resize2fs 'exit 1'
expand_on /dev/sda2 sda 2
same "resize2fs fails: ends with code 1" "$code" "1"
rm -f "$W/bin/resize2fs"

expand_on /dev/vda "" ""
same "a file system on a whole disk: no partition is grown" "$(grow_call)" ""
has "a file system on a whole disk: the file system is grown" "$W/calls.log" "resize2fs /dev/vda"
same "a file system on a whole disk: ends with code 0" "$code" "0"

FS_TYPE=btrfs expand_on /dev/sda2 sda 2
same "another file system type: ends with code 1" "$code" "1"
same "another file system type: nothing is changed" "$(calls | grep -cE '^(growpart|resize2fs)')" "0"

expand_on /dev/sda2 sda 2
is "the output is also written to the log file" grep -q "Auto-Expand Root Filesystem" "$W/root/var/log/diskexpand.log"
hasnt "the script does not install packages (it runs at every start)" "$FILES/expandVirtualFilesystem" "apt-get install -y"

finish

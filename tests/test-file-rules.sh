#!/usr/bin/env bash
# Small rules for the files of the repo and for how the build installs them.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

# every text file ends with a line end (a tool that adds a line to a file without one glues
# the new line onto the last one)
missing=""
while IFS= read -r file; do
  case "$file" in *.png | *.gif | *.jpg) continue ;; esac
  [ -s "$REPO/$file" ] || continue
  [ "$(tail -c 1 "$REPO/$file" | od -An -c | tr -d ' ')" = '\n' ] || missing="$missing $file"
done < <(git -C "$REPO" ls-files)
same "every text file ends with a line end" "$missing" ""

# how the Homebridge stage installs its files: text files 644, programs 755
run_stage 01-homebridge 00-run.sh
same "the Homebridge stage ends with code 0" "$STAGE_CODE" "0"
mode() { stat -c '%a' "$W/root/$1"; }
same "/etc/issue is a text file (644)" "$(mode etc/issue)" "644"
for unit in first-boot-homebridge hb-expand-rootfs hb-vm-issue hb-ssh-host-keys; do
  same "$unit.service is a text file (644)" "$(mode "etc/systemd/system/$unit.service")" "644"
done
for program in usr/local/sbin/hb-config usr/local/sbin/first-boot-homebridge usr/local/sbin/expandVirtualFilesystem usr/local/sbin/updateIssueVMName etc/hb-service/homebridge/prestart.d/20-hb-nginx-check etc/update-motd.d/20-homebridge; do
  same "$program is a program (755)" "$(mode "$program")" "755"
done
same "nothing is left in /tmp of the image by the stage" "$(find "$W/root/tmp" -mindepth 1 | wc -l | tr -d ' ')" "0"
hasnt "the stage no longer copies a file that nothing used" "$REPO/assets/01-homebridge/00-run.sh" "bashrc.partial"

# the login message: its text must not be used as a printf format
MOTD="$FILES/motd-homebridge"
mkdir -p "$W/root/etc"
echo "9000" > "$W/root/etc/hb-ui-port"
echo "2026-01-02 100%s" > "$W/root/etc/hb-release"
fake hostname 'case "$1" in -I) echo "192.168.1.20 fd00::20" ;; *) echo "my-vm" ;; esac'
in_sandbox "$MOTD" > "$W/motd"
PATH="$W/bin:$PATH" bash "$W/motd" > "$W/motd.out" 2>&1
has "the login message shows the image version as it is (a % sign is not read as a format)" "$W/motd.out" "Homebridge VM Image 2026-01-02 100%s"
has "the login message shows the address with the UI port" "$W/motd.out" "http://my-vm.local:9000"
has "an IPv6 address is put in brackets" "$W/motd.out" "http://[fd00::20]:9000"

# both CPU types are built at the same time
isnt "the two image builds do not wait for each other" grep -q 'max-parallel: 1' "$REPO/.github/workflows/release-stage-2_build_and_push_images.yml"

finish

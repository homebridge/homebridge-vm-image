#!/usr/bin/env bash
# The checks of the boot test. scripts/boot-test.sh runs this file INSIDE the started VM, as root.
# It prints one line per check ("ok ..." or "FAIL ...") and ends with code 1 when a check failed.
#
# Arguments: <expected text in /etc/hb-release, or -> <expected Homebridge apt package version, or -> <smallest size of / in GB>
set -u

EXPECTED_RELEASE="${1:--}"
EXPECTED_APT_VERSION="${2:--}"
MIN_ROOT_GB="${3:-0}"

FAILED=0
ok() { printf 'ok    %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL  %s\n' "$1"
  shift
  [ $# -gt 0 ] && printf '      %s\n' "$@"
  return 0
}
# check <text> <command...>: passes when the command succeeds
check() {
  local text="$1" out
  shift
  if out="$("$@" 2>&1)"; then ok "$text"; else fail "$text" "$(printf '%s' "$out" | tail -n 5)"; fi
}
same() { if [ "$2" = "$3" ]; then ok "$1"; else fail "$1" "expected: $3" "actual:   $2"; fi; }

# wait_for <seconds> <command...>: tries the command until it succeeds
wait_for() {
  local seconds="$1" start
  shift
  start=$(date +%s)
  until "$@" > /dev/null 2>&1; do
    [ $(($(date +%s) - start)) -ge "$seconds" ] && return 1
    sleep 5
  done
}
http_code() { curl -s -o /dev/null --max-time 10 -w '%{http_code}' "$1" 2> /dev/null; }
ui_answers() { [ "$(http_code http://127.0.0.1:8581/)" = "200" ]; }
nginx_answers() { [ "$(http_code http://127.0.0.1/)" = "200" ]; }

echo "--- Homebridge"
if wait_for 420 ui_answers; then ok "the Homebridge UI answers on port 8581"; else fail "the Homebridge UI answers on port 8581" "$(journalctl -b -u homebridge --no-pager | tail -n 15)"; fi
check "the Homebridge service is active" systemctl is-active homebridge
if wait_for 60 nginx_answers; then ok "nginx passes port 80 on to the UI"; else fail "nginx passes port 80 on to the UI" "http code: $(http_code http://127.0.0.1/)"; fi
check "nginx accepts its config" nginx -t
check "Node.js runs" /opt/homebridge/bin/node --version
check "ffmpeg runs" ffmpeg -version

same "loading the VM settings prints nothing (as root, the way hb-shell does)" "$(bash -c '. /opt/homebridge/source.sh' 2>&1)" ""
same "the Homebridge start log has no shell error and no 'Unknown VM' line" "$(journalctl -b -u homebridge --no-pager | grep -ciE 'Unknown VM|not found')" "0"
same "the settings name the VM program" "$(sh -c '. /opt/homebridge/source-vm.sh; echo "$VM_SOFTWARE"')" "QEMU / UTM"
check "the login screen names the VM program" grep -q 'VM Software:' /etc/issue

same "the UI's restart and shut down buttons can work: the homebridge user may run these, and only these, as root" \
  "$(sudo -u homebridge sudo -n -l 2> /dev/null | sed -n 's/^ *(root) NOPASSWD: //p')" \
  "/sbin/shutdown, /sbin/reboot, /sbin/poweroff, /usr/sbin/shutdown, /usr/sbin/reboot, /usr/sbin/poweroff"
same "the homebridge user is in no extra group" "$(id -Gn homebridge)" "homebridge"

echo "--- versions"
if [ "$EXPECTED_RELEASE" != "-" ]; then
  same "/etc/hb-release holds the release" "$(cat /etc/hb-release 2> /dev/null)" "$EXPECTED_RELEASE"
fi
if [ "$EXPECTED_APT_VERSION" != "-" ]; then
  same "the Homebridge apt package is the pinned version" "$(dpkg-query -W -f='${Version}' homebridge 2> /dev/null)" "$EXPECTED_APT_VERSION"
fi

echo "--- package sources and updates"
CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
check "apt knows the Debian security source" sh -c "apt-cache policy | grep -q '${CODENAME}-security'"
check "apt knows the Debian updates source" sh -c "apt-cache policy | grep -q '${CODENAME}-updates'"
check "apt knows the Homebridge source" sh -c "apt-cache policy | grep -q 'repo.homebridge.io'"
same "automatic updates take Debian security fixes only" \
  "$(apt-config dump | sed -n 's/^Unattended-Upgrade::Origins-Pattern:: //p')" "\"origin=Debian,codename=\${distro_codename}-security,label=Debian-Security\";"
check "automatic updates never restart the VM" sh -c "apt-config dump | grep -qx 'Unattended-Upgrade::Automatic-Reboot \"false\";'"
check "the daily update timer is on" systemctl is-enabled apt-daily-upgrade.timer

echo "--- made on this VM, not in the image"
check "the VM made its own machine id" grep -qE '^[0-9a-f]{32}$' /etc/machine-id
same "the VM made its SSH host keys" "$(find /etc/ssh -maxdepth 1 -name 'ssh_host_*_key' | wc -l)" "3"
check "the SSH server is active" systemctl is-active ssh

echo "--- time"
check "no unit looks up the timezone at every start any more" sh -c '! systemctl cat tzupdate.service > /dev/null 2>&1'
check "the one-time timezone lookup is switched on" systemctl is-enabled hb-timezone-once
check "the time sync service is switched on" systemctl is-enabled systemd-timesyncd
check "the time sync service is active" systemctl is-active systemd-timesyncd
same "the system says time sync is in use" "$(timedatectl show -p NTP --value)" "yes"

echo "--- boot loader"
DEB_ARCH="$(dpkg --print-architecture)"
case "$DEB_ARCH" in
  amd64) REMOVABLE=/boot/efi/EFI/BOOT/BOOTX64.EFI ;;
  *) REMOVABLE=/boot/efi/EFI/BOOT/BOOTAA64.EFI ;;
esac
check "the boot loader is in the place every VM program looks in" test -s "$REMOVABLE"
check "the boot loader is in Debian's own place too" test -d /boot/efi/EFI/debian
same "each console is on the kernel line once" "$(tr ' ' '\n' < /proc/cmdline | grep -c '^console=tty0$')" "1"
same "the screen is the last console (it gets the start-up messages and the emergency prompt)" "$(tr ' ' '\n' < /proc/cmdline | grep '^console=' | tail -n 1)" "console=tty0"
check "no made-up GRUB folder is left in the image" test ! -e /usr/lib/grub/amd64-efi
# What a later update of the GRUB package does: its set-up step runs again. It must write a
# fresh copy of the boot loader to the boot partition.
touch -d '2001-01-01' "$REMOVABLE"
if dpkg-reconfigure -f noninteractive "grub-efi-${DEB_ARCH}" > /tmp/grub-reconfigure.log 2>&1 && [ "$(date -r "$REMOVABLE" +%Y)" != "2001" ]; then
  ok "an update of the GRUB package refreshes the boot loader on the boot partition"
else
  fail "an update of the GRUB package refreshes the boot loader on the boot partition" "$(tail -n 5 /tmp/grub-reconfigure.log)"
fi

echo "--- start order"
same "systemd found no loop in the start order" "$(journalctl -b --no-pager | grep -ciE 'ordering cycle|to break ordering')" "0"
# The start of the system must finish while the setup wizard still waits for a person.
if wait_for 120 systemctl is-active multi-user.target; then ok "the system finished starting (multi-user.target) while the wizard waits"; else fail "the system finished starting (multi-user.target) while the wizard waits" "$(systemctl list-jobs --no-legend --plain)"; fi
check "all login prompts are done with their start (getty.target)" systemctl is-active getty.target
same "no start job is left waiting" "$(systemctl list-jobs --no-legend --plain | awk '{print $2}' | tr '\n' ' ')" ""
same "the setup wizard is running" "$(systemctl show -p ActiveState --value first-boot-homebridge)" "active"
check "the wizard is what the screen console shows" sh -c "tr -d '\\0' < /dev/vcs1 | grep -q 'Homebridge VM Image Setup'"
same "the login prompt of the screen console is not started while the wizard uses the console" "$(systemctl is-active 'getty@tty1.service')" "inactive"

echo "--- the system as a whole"
same "no unit failed" "$(systemctl --failed --no-legend --plain | awk '{print $1}' | tr '\n' ' ')" ""
ROOT_GB="$(df --output=size -BG / | tail -n 1 | tr -dc '0-9')"
if [ "${ROOT_GB:-0}" -ge "$MIN_ROOT_GB" ]; then ok "the root file system is ${ROOT_GB} GB (at least ${MIN_ROOT_GB} GB)"; else fail "the root file system is at least ${MIN_ROOT_GB} GB" "it is ${ROOT_GB} GB"; fi

echo "--- when the wizard ends"
# (this check changes the state of the VM, so it comes last)
systemctl stop first-boot-homebridge
if wait_for 30 systemctl is-active 'getty@tty1.service'; then ok "the login prompt of the screen console comes up when the wizard ends"; else fail "the login prompt of the screen console comes up when the wizard ends" "$(systemctl status 'getty@tty1.service' --no-pager 2>&1 | tail -n 5)"; fi
check "the 'wizard is running' file is gone" test ! -e /run/hb-first-boot-wizard

echo "--- facts (not checks)"
echo "kernel: $(uname -r)   Debian: $(cat /etc/debian_version)   up: $(cut -d' ' -f1 /proc/uptime)s"
echo "time zone: $(timedatectl show -p Timezone --value 2> /dev/null)   virtualisation: $(systemd-detect-virt 2> /dev/null)"
df -h / | tail -n 1
echo "system state: $(systemctl is-system-running 2> /dev/null)   multi-user.target: $(systemctl is-active multi-user.target)"
systemctl list-jobs --no-legend --plain | sed 's/^/job: /'
systemctl list-timers --no-pager --no-legend | awk '{print "timer: " $(NF-1) " -> " $NF}'

[ "$FAILED" -eq 0 ] || { echo "$FAILED checks failed"; exit 1; }
echo "all checks passed"

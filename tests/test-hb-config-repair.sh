#!/usr/bin/env bash
# shellcheck disable=SC2016  # single quotes are meant: that text must reach the fake commands as it is
# hb-config -> "Update" brings a VM that was made from an older image up to what a new image
# has: the Debian sources for security fixes, SSH host keys of its own, and time sync
# (decided by BP, 2026-11-21). On a VM from a current image it must change nothing.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

R="$W/root"
EXTRA="$R/etc/apt/sources.list.d/debian-security-updates.list"
MARKER="$R/var/lib/hb-image/ssh-host-keys-made"

# old_vm: a VM as an image from before December 2026 leaves it (Debian 12, one package source,
# host keys from the image, no time sync). The yes/no questions take their answers, in order,
# from the arguments (YES or NO); with no answer left, the answer is YES.
old_vm() {
  rm -rf "${R:?}" "${W:?}/calls.log" "${W:?}/bin" "${W:?}/count"
  mkdir -p "$W/bin" "$R/etc/apt/sources.list.d" "$R/etc/ssh" "$R/usr/bin" "$R/var/lib" "$R/tmp" "$R/lib/systemd/system" "$R/usr/lib/systemd/system"
  printf 'PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"\nVERSION_CODENAME=bookworm\n' > "$R/etc/os-release"
  echo "deb http://deb.debian.org/debian bookworm main" > "$R/etc/apt/sources.list"
  echo "deb [signed-by=/usr/share/keyrings/homebridge.gpg] https://repo.homebridge.io stable main" > "$R/etc/apt/sources.list.d/homebridge.list"
  echo "homebridge-vm" > "$R/etc/hostname"
  for kind in ecdsa ed25519 rsa; do
    echo "key from the image" > "$R/etc/ssh/ssh_host_${kind}_key"
    echo "key from the image" > "$R/etc/ssh/ssh_host_${kind}_key.pub"
  done
  printf '#!/bin/sh\n' > "$R/usr/bin/ssh-keygen" && chmod +x "$R/usr/bin/ssh-keygen"
  printf '%s\n' "$@" > "$W/answers"
  cat > "$W/bin/whiptail" <<FAKE
#!/bin/sh
echo "whiptail \$*" >> "$W/calls.log"
case "\$*" in *--yesno*) ;; *) exit 0 ;; esac
n=\$(cat "$W/count" 2>/dev/null || echo 0); n=\$((n + 1)); echo "\$n" > "$W/count"
[ "\$(sed -n "\${n}p" "$W/answers")" = "NO" ] && exit 1
exit 0
FAKE
  chmod +x "$W/bin/whiptail"
  fake apt-get
  fake apt-mark 'case "$1" in showhold) cat "'"$W"'/held" 2>/dev/null ;; esac; exit 0'
  fake systemctl
  # ssh-keygen -A -f <folder>: makes the three kinds of keys under <folder>/etc/ssh
  fake ssh-keygen 'dir=""; while [ $# -gt 0 ]; do [ "$1" = "-f" ] && dir="$2"; shift; done; for k in ecdsa ed25519 rsa; do echo "key made on this VM" > "$dir/etc/ssh/ssh_host_${k}_key"; echo "key made on this VM" > "$dir/etc/ssh/ssh_host_${k}_key.pub"; done'
  rm -f "$W/held"
}
apt_calls() { calls | sed -n 's/^apt-get //p' | tr '\n' ';'; }
keys() { cat "$R"/etc/ssh/ssh_host_*_key | sort -u; }

# ---- an older VM, yes to everything
old_vm
hb_config do_system_repair
has "an older VM: the user is asked first, with the list of fixes" "$W/calls.log" "This VM was made from an older image"
is "the Debian security and updates sources are added" test -s "$EXTRA"
has "the security source of this Debian release" "$EXTRA" "deb https://deb.debian.org/debian-security bookworm-security main"
has "the updates source of this Debian release" "$EXTRA" "deb https://deb.debian.org/debian bookworm-updates main"
same "the source the VM had is left as it is" "$(cat "$R/etc/apt/sources.list")" "deb http://deb.debian.org/debian bookworm main"
same "the lists are read, the waiting updates are installed, and time sync is installed" "$(apt_calls)" \
  "update;-y -o Dpkg::Options::=--force-confold dist-upgrade;install -y systemd-timesyncd;"
has "the Homebridge package is held back while the Debian updates are installed" "$W/calls.log" "apt-mark hold homebridge"
has "and released again afterwards" "$W/calls.log" "apt-mark unhold homebridge"
has "time sync is switched on" "$W/calls.log" "systemctl enable --now systemd-timesyncd"
same "the VM has SSH host keys of its own now" "$(keys)" "key made on this VM"
same "all three kinds of keys are there, each with its public half" "$(find "$R/etc/ssh" -name 'ssh_host_*' | wc -l | tr -d ' ')" "6"
same "only root can read a private key" "$(stat -c '%a' "$R/etc/ssh/ssh_host_ed25519_key")" "600"
is "it is written down that the keys were made here" test -e "$MARKER"
has "the SSH server reads the new keys" "$W/calls.log" "systemctl restart ssh"
has "the user is told how to accept the new key" "$W/calls.log" "ssh-keygen -R homebridge-vm.local"
same "nothing is left in the temp folder" "$(find "$R/tmp" -mindepth 1 | wc -l | tr -d ' ')" "0"

# ---- a second run: nothing is needed, nothing is asked
touch "$R/usr/lib/systemd/system/systemd-timesyncd.service"
rm -f "${W:?}/calls.log"
hb_config do_system_repair
same "a second run asks nothing and changes nothing" "$(calls | wc -l | tr -d ' ')" "0"

# ---- a VM from a current image (Debian 13)
old_vm
printf 'VERSION_CODENAME=trixie\n' > "$R/etc/os-release"
rm -f "$R/etc/apt/sources.list"
printf 'Types: deb\nURIs: https://deb.debian.org/debian-security\nSuites: trixie-security\n' > "$R/etc/apt/sources.list.d/debian.sources"
mkdir -p "$R/var/lib/hb-image" && touch "$MARKER" "$R/usr/lib/systemd/system/systemd-timesyncd.service"
hb_config do_system_repair
same "a VM from a current image: nothing is asked and nothing is changed" "$(calls | wc -l | tr -d ' ')" "0"
same "a VM from a current image: its keys are untouched" "$(keys)" "key from the image"

# ---- the user says no
old_vm NO
hb_config do_system_repair
isnt "no to the first question: no source is added" test -e "$EXTRA"
same "no to the first question: nothing is installed" "$(apt_calls)" ""
same "no to the first question: the keys are untouched" "$(keys)" "key from the image"

old_vm YES NO NO
hb_config do_system_repair
is "yes, then no to the updates: the sources are still added" test -s "$EXTRA"
same "yes, then no to the updates: no update is installed" "$(apt_calls | grep -c dist-upgrade)" "0"
same "no to the new keys: the keys are untouched" "$(keys)" "key from the image"
isnt "no to the new keys: nothing is written down, so the question comes again next time" test -e "$MARKER"

# ---- things that fail
old_vm
fake apt-get 'case "$1" in update) exit 100 ;; esac; exit 0'
hb_config do_system_repair
isnt "no network: the new sources file is taken out again, so apt keeps working" test -e "$EXTRA"
has "no network: the user is told" "$W/calls.log" "could not be added"

old_vm
fake ssh-keygen 'exit 1'
hb_config do_system_repair
same "the keys can not be made: the old keys stay in place (the SSH server still starts)" "$(keys)" "key from the image"
isnt "the keys can not be made: nothing is written down" test -e "$MARKER"
has "the keys can not be made: the user is told" "$W/calls.log" "The old keys were left in place"

old_vm
echo "homebridge" > "$W/held"
hb_config do_system_repair
same "a Homebridge package the user holds back stays held back" "$(calls | grep -c 'apt-mark unhold')" "0"

# ---- a system the tool does not know
old_vm
printf 'VERSION_CODENAME="we ird"\n' > "$R/etc/os-release"
hb_config 'repair_needs_sources && echo NEEDED'
hasnt "an odd release name: no source lines are written for it" "$W/hb-config.log" "NEEDED"

# ---- "Update" runs the fixes first, then the update of the tool itself
has "the Update menu entry runs the fixes" "$FILES/hb-config" '  do_system_repair'
same "Update: first the fixes, then the tool" "$(sed -n '/^do_update() {$/,/^}$/p' "$FILES/hb-config" | grep -c 'do_system_repair\|do_update_tool')" "2"

finish

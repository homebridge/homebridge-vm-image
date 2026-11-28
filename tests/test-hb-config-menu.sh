#!/usr/bin/env bash
# shellcheck disable=SC2016  # single quotes are meant: that text must reach the script under test as it is
# The smaller parts of hb-config: the hostname, the menus, and leftovers from the Raspberry Pi tool.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

TOOL="$FILES/hb-config"
R="$W/root"

is "the tool is a /bin/sh script that dash accepts" dash -n "$TOOL"
same "its first line names /bin/sh" "$(head -n 1 "$TOOL")" "#!/bin/sh"

# hostname <typed name>
hostname_to() {
  rm -rf "${R:?}" "${W:?}/calls.log" "${W:?}/bin"
  mkdir -p "$W/bin" "$R/etc"
  echo "homebridge-vm" > "$R/etc/hostname"
  printf '127.0.0.1 localhost\n127.0.1.1 homebridge-vm\n' > "$R/etc/hosts"
  fake whiptail "case \"\$*\" in *--inputbox*) printf '%s' '$1' >&2 ;; esac; exit 0"
  fake systemctl 'exit 1'
  fake hostnamectl
  hb_config do_hostname
}

hostname_to my-vm
same "the new hostname is written" "$(cat "$R/etc/hostname")" "my-vm"
has "the hosts file follows" "$R/etc/hosts" "$(printf '127.0.1.1\tmy-vm')"
has "the message is about the hostname" "$W/calls.log" "The hostname has been changed to 'my-vm'"
hasnt "the message no longer says the filesystem was expanded" "$W/calls.log" "filesystem has been expanded"

hostname_to 'bad name; reboot'
same "a name with other characters is refused: the hostname stays" "$(cat "$R/etc/hostname")" "homebridge-vm"
has "a refused name is reported" "$W/calls.log" "can not be used as a hostname"

# leftovers from the Raspberry Pi tool
hasnt "the tool no longer makes the Raspberry Pi file /boot/config.txt" "$TOOL" "/boot/config.txt"
for gone in is_live is_ssh is_fkms is_installed deb_ver set_config_var get_web_addresses get_ip_and_port get_first_user do_nmtui; do
  isnt "the unused function $gone is gone" grep -q "^$gone *()" "$TOOL"
done
hasnt "the menu no longer promises 'the latest LTS version' of Node.js" "$TOOL" "latest LTS version"
has "the timezone can be changed from the Advanced menu" "$TOOL" '"A3 Change Timezone"'
has "expanding the filesystem no longer asks for a reboot" "$TOOL" "No restart is needed"

finish

#!/usr/bin/env bash
# shellcheck disable=SC2016  # single quotes are meant: the text is looked for, or passed on, as it is
# Automatic updates: security fixes only, never a restart, and never the Homebridge package or
# Node.js (decided by BP, 2026-11-21).
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

STAGE="$REPO/assets/01-homebridge"

has "the stage installs unattended-upgrades" "$STAGE/00-packages" "unattended-upgrades"

run_stage 01-homebridge 00-run.sh
same "the stage ends with code 0" "$STAGE_CODE" "0"

CONF="$W/root/etc/apt/apt.conf.d/52unattended-upgrades-homebridge"
is "the settings file is installed" test -f "$CONF"

# the list of sources, without the comment lines
ORIGINS="$(sed -n '/^Unattended-Upgrade::Origins-Pattern {/,/^};/p' "$CONF" | grep '"')"
same "one source only: the Debian security fixes" "$(printf '%s\n' "$ORIGINS" | tr -s ' ')" ' "origin=Debian,codename=${distro_codename}-security,label=Debian-Security";'
has "Debian's own, wider list is cleared first" "$CONF" "#clear Unattended-Upgrade::Origins-Pattern;"
has "the Homebridge package is never touched" "$CONF" '"homebridge";'
has "Node.js is never touched" "$CONF" '"nodejs";'
has "the VM is never restarted" "$CONF" 'Unattended-Upgrade::Automatic-Reboot "false";'
hasnt "no restart setting says true" "$CONF" 'Automatic-Reboot "true"'

AUTO="$W/root/etc/apt/apt.conf.d/20auto-upgrades"
has "the daily run is switched on" "$AUTO" 'APT::Periodic::Unattended-Upgrade "1";'
has "the timers are switched on" "$W/chroot-script" "systemctl enable apt-daily.timer apt-daily-upgrade.timer"
has "the build checks the settings as apt reads them" "$W/chroot-script" "apt-config dump"

finish

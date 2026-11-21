#!/usr/bin/env bash
# shellcheck disable=SC2016  # single quotes are meant: the text is looked for as it is
# The boot loader (GRUB) set-up: the right name for each CPU type, a boot partition that later
# GRUB updates can refresh, and kernel options that are written once.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

GRUB_DEFAULT="$W/root/etc/default/grub"
grub_install_call() { calls | grep '^grub-install' | tr -s ' '; }
kernel_options() { sed -n 's/^GRUB_CMDLINE_LINUX="\(.*\)"$/\1/p' "$GRUB_DEFAULT"; }

base_setup amd64
same "amd64: the base setup ends with code 0" "$BASE_SETUP_CODE" "0"
case "$(grub_install_call)" in *"--target=x86_64-efi "*) ok "amd64: GRUB is installed for x86_64-efi (GRUB's name for Intel/AMD)" ;; *) fail "amd64: GRUB is installed for x86_64-efi (GRUB's name for Intel/AMD)" "$(grub_install_call)" ;; esac
case "$(grub_install_call)" in *"--force-extra-removable"*) ok "amd64: the boot loader goes to Debian's place and to the place every VM program looks in" ;; *) fail "amd64: the boot loader goes to Debian's place and to the place every VM program looks in" "$(grub_install_call)" ;; esac
same "amd64: later GRUB updates refresh the boot partition too" "$(cat "$W/debconf-selections")" "grub-efi-amd64 grub2/force_efi_extra_removable boolean true"
same "amd64: the kernel options name the serial port first and the screen last" "$(kernel_options)" "console=ttyS0 console=tty0 root=UUID=ROOT-UUID"
same "amd64: the second variable for kernel options is empty (GRUB adds both to the kernel line)" "$(sed -n 's/^GRUB_CMDLINE_LINUX_DEFAULT=//p' "$GRUB_DEFAULT")" '""'
# (the mount point is left out: the test moved the paths of the script into its scratch folder)
same "the boot partition is checked after the root file system (order 2)" "$(awk '$3 == "vfat" {print $1, $3, $4, $5, $6}' "$W/root/etc/fstab")" "UUID=ESP-UUID vfat umask=0077 0 2"
same "the root file system is checked first (order 1)" "$(awk '$3 == "ext4" {print $1, $2, $3, $4, $5, $6}' "$W/root/etc/fstab")" "UUID=ROOT-UUID / ext4 defaults,noatime 0 1"

base_setup arm64
case "$(grub_install_call)" in *"--target=arm64-efi "*) ok "arm64: GRUB is installed for arm64-efi" ;; *) fail "arm64: GRUB is installed for arm64-efi" "$(grub_install_call)" ;; esac
same "arm64: the serial port is ttyAMA0" "$(kernel_options)" "console=ttyAMA0 console=tty0 root=UUID=ROOT-UUID"
same "arm64: later GRUB updates refresh the boot partition too" "$(cat "$W/debconf-selections")" "grub-efi-arm64 grub2/force_efi_extra_removable boolean true"

# a GRUB that does not write the boot loader must stop the build
fake grub-install 'exit 0'
base_setup arm64
isnt "the build stops when the boot loader file is not on the boot partition" test "$BASE_SETUP_CODE" -eq 0
has "it says which file is missing" "$W/base-setup.log" "is missing"
rm -f "$W/bin/grub-install"

BUILD="$REPO/build-debian-image.sh"
hasnt "the build no longer copies the build machine's GRUB files into the image" "$BUILD" "usr/lib/grub"
hasnt "the build machine no longer needs GRUB packages" "$REPO/scripts/install-build-deps.sh" "grub-efi"
hasnt "the block that looked for a file that was already in place is gone" "$REPO/scripts/chroot-base-setup.sh" "Create fallback EFI bootloader"

finish

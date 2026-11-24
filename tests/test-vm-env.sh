#!/usr/bin/env bash
# The VM detection and the image versions: one file, /opt/homebridge/source-vm.sh (the name the
# Homebridge apt package loads).
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

run_stage 01-homebridge 00-run.sh
same "the Homebridge stage ends with code 0" "$STAGE_CODE" "0"

ENV_FILE="$W/root/opt/homebridge/source-vm.sh"
is "the file is installed where the apt package loads it" test -f "$ENV_FILE"
is "it is plain sh" dash -n "$ENV_FILE"
has "the image versions are written to that file" "$W/chroot-script" ">> /opt/homebridge/source-vm.sh"
hasnt "the stage does not call sudo inside the new system" "$W/chroot-script" "| sudo "

# the settings file itself, in the shell that loads it (dash), with a stand-in for systemd-detect-virt
vm_env() { # vm_env <answer of systemd-detect-virt> [exit code]
  fake systemd-detect-virt "echo '$1'; exit ${2:-0}"
  PATH="$W/bin:$PATH" dash -euc ". '$FILES/source-vm.sh'; echo \"VM_SOFTWARE=[\${VM_SOFTWARE-unset}]\"" 2>&1
}
same "QEMU: named after the UTM package (as the old image did), and nothing else is printed" "$(vm_env qemu)" "VM_SOFTWARE=[UTM]"
same "KVM (Proxmox and others)" "$(vm_env kvm)" "VM_SOFTWARE=[KVM]"
same "VirtualBox" "$(vm_env oracle)" "VM_SOFTWARE=[VirtualBox]"
same "Hyper-V is known (it printed 'Unknown VM' before)" "$(vm_env microsoft)" "VM_SOFTWARE=[Hyper-V]"
same "VMware is known" "$(vm_env vmware)" "VM_SOFTWARE=[VMware]"
same "a VM program it does not know: nothing is printed, the name is not set" "$(vm_env something-new)" "VM_SOFTWARE=[unset]"
same "no VM at all (the tool answers 'none' with code 1): no error under 'set -e'" "$(vm_env none 1)" "VM_SOFTWARE=[unset]"

BUILD="$REPO/build-debian-image.sh"
hasnt "the build no longer adds a second loader block to the apt package's source.sh" "$BUILD" "Appended by homebridge-vm-image"
has "the build stops if the apt package no longer loads the VM settings" "$BUILD" "no longer loads /opt/homebridge/source-vm.sh"

has "the login screen script loads the same file" "$FILES/updateIssueVMName" ". /opt/homebridge/source-vm.sh"
finish

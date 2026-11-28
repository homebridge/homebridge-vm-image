# shellcheck shell=sh
# Homebridge VM image: which VM program this system runs in, and the versions of the image.
#
# The Homebridge apt package loads this file (/opt/homebridge/source-vm.sh) from /bin/sh scripts
# (on Debian /bin/sh is dash), and updateIssueVMName loads it for the login screen. So:
#   - Keep this file plain sh: no [[ ]], no arrays, no "source".
#   - It must print nothing: it is loaded at every start of Homebridge, by every
#     "sudo hb-shell" and at every upgrade of the Homebridge package.
#   - It must work in a script that runs with "set -e" and "set -u".
#
# systemd-detect-virt names the VM program. A program it does not know leaves VM_SOFTWARE unset.

case "$(systemd-detect-virt 2> /dev/null || true)" in
  # qemu: the UTM package (the only QEMU-based package we ship). The name is what users report
  # back, so it follows the package, not the hypervisor under it.
  qemu) VM_SOFTWARE="UTM" ;;
  kvm) VM_SOFTWARE="KVM" ;;
  oracle) VM_SOFTWARE="VirtualBox" ;;
  microsoft) VM_SOFTWARE="Hyper-V" ;;
  vmware) VM_SOFTWARE="VMware" ;;
  parallels) VM_SOFTWARE="Parallels" ;;
  apple) VM_SOFTWARE="Apple Virtualization" ;;
  xen) VM_SOFTWARE="Xen" ;;
  bhyve) VM_SOFTWARE="bhyve" ;;
  *) VM_SOFTWARE="" ;;
esac

if [ -n "$VM_SOFTWARE" ]; then
  export VM_SOFTWARE
else
  unset VM_SOFTWARE
fi

# The build adds the versions of the image below this line.

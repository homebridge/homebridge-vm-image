# Homebridge VM image: which VM program this system runs in, and the versions of the image.
#
# /opt/homebridge/source-vm.sh loads this file, and the Homebridge apt package loads that one
# from /bin/sh scripts (on Debian /bin/sh is dash). So:
#   - Keep this file plain sh: no [[ ]], no arrays, no "source".
#   - It must print nothing: it is loaded at every start of Homebridge, by every
#     "sudo hb-shell" and at every upgrade of the Homebridge package.
#   - It must work in a script that runs with "set -e" and "set -u".
#
# systemd-detect-virt names the VM program. A program it does not know leaves VM_SOFTWARE unset.

case "$(systemd-detect-virt 2> /dev/null || true)" in
  qemu) VM_SOFTWARE="QEMU / UTM" ;;
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

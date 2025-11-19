#!/bin/bash

VM_NAME="homebridge-validation-vm"

# Stop VM if running
VBoxManage controlvm "$VM_NAME" poweroff 2>/dev/null || true
sleep 2

# Unregister VM
VBoxManage unregistervm "$VM_NAME" --delete 2>/dev/null || true

# Remove all orphaned disks from the media registry
VBoxManage list hdds | grep -E "^UUID:|^Location:" | while read -r line; do
    if [[ "$line" =~ ^UUID:[[:space:]]+(.+)$ ]]; then
        UUID="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ homebridge.*\.vmdk$ ]]; then
        echo "Removing orphaned disk: $UUID"
        VBoxManage closemedium disk "$UUID" 2>/dev/null || true
    fi
done

# Remove VM directory if it still exists
rm -rf ~/VirtualBox\ VMs/homebridge-validation-vm/

echo "Cleanup complete. Ready to import OVA."

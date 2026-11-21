#! /bin/bash

KEYBOARD=`cat /proc/bus/input/devices | grep 'Name=' | grep Keyboard`

if [[ $KEYBOARD == *"QEMU"* ]]; then
    export VM_SOFTWARE="UTM"
elif [[ $KEYBOARD == *"VirtualBox"* ]]; then
    export VM_SOFTWARE="VirtualBox"
elif [[ $KEYBOARD == *"Parallels"* ]]; then
    export VM_SOFTWARE="Parallels"
else
    echo "Unknown VM ${KEYBOARD}"
fi


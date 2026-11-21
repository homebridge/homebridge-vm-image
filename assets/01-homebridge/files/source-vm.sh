# Loaded by the Homebridge apt package (/opt/homebridge/source.sh), which is a /bin/sh script.
# Keep this file plain sh.
#
# The apt package gives the files in /opt/homebridge to the user Homebridge runs as, so nothing
# is decided in this file. It only loads the file below, which belongs to root and is outside
# that folder.
if [ -r /usr/local/lib/homebridge-vm/vm-env.sh ]; then
  . /usr/local/lib/homebridge-vm/vm-env.sh
fi

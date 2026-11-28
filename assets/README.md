# What goes into the image

Each numbered folder is one build stage. `build-debian-image.sh` runs them in name order:

- `00-packages`: Debian packages to install, one per line.
- `NN-run.sh`: copies the files in `files/` into the new system and runs commands inside it (`on_chroot`).

The stages were first copied from homebridge-raspbian-image and then changed for a VM. Files that are still shared with the Raspberry Pi image (keep fixes in step): `20-hb-nginx-check`, `homebridge.local`, `custom_502.html`, `nginx-homebridge-self-signed-cert` and most of `hb-config`.

`Console.png`, `First Boot.png` and `homebridge-icon.png` are used by the wiki and the VM packages. Do not rename them.

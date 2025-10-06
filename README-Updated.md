# Homebridge VM Boot Image

A preconfigured Debian Virtual Disk Image for X86 and Arm cpu architecture that runs Homebridge.

The virtual disk is created similar to how the Homebridge Raspbian image is created, and leverages Debian as the Operating System, with NodeJs, Homebridge and the Homebridge UI already installed.

<p align="center">
  <img src="assets/Console.png">
</p>

## Appliance Images Available:

| File | Usage |
|:-------:|:-------:|
| OVA | Open Virtual Appliance optimized for VirtualBox |
| UTM | UTM Appliance |
| HYPERV | Microsoft HyperV Virtual Machine |

## Virtual Disk Images

| File | Usage |
|:-------:|:-------:|
| QCOW2 | QEMU/KVM Virtual Hard Diskt, also leveraged by Virtual Box |
| VDI | Virtual Disk Image |
| VHDX | Microsoft HyperV Virtual Hard Disk |
| VMDK | VMware Virtual Hard Disk |

## Supported CPU Architectures:

| CPU Architecture | Description |
|:-------:|:-------:|
| amd64 | 64 Bit Intel X86 and AMD Cpu's |
| arm64 | 64 Bit Arm CPU's including M based Mac's |

# Virtual Disk Image Specifications

* OS: Debian 12 ( aka `Bookworm` ) Lite
* CPU Architecture: X86/Intel/AMD64 and ARM ( Includes M cpu based Macs )
* Virtual Disk Size: Allocated as a 5Gb Virtual Hard Drive for VHDX and VMDK and 50Gb for gcow2 and VDI.
* Packages Installed: NodeJS, Homebridge, Homebridge UI and ffmpeg.  Exact versions installed are listed in the Manifest file.
* Guest Additions: **UTM** and HyperV Kernel Modules Installed

> **Note**: This VM image uses the official [Homebridge](https://github.com/homebridge/homebridge) packages from the official APT repository. If you were previously using images based on `oznu/homebridge` or from the old [`homebridge-vm-image-boot2docker`](https://github.com/homebridge/homebridge-vm-image-boot2docker) repository (v0.0.4), these new VM images provide the updated official Homebridge distribution.

## Release Streams

Virtual Disk Images are supplied supporting the various Homebridge Release Streams.
- Stable/Latest: Most recent releases of NodeJS, Homebridge, Homebridge UI, and FFMPEG
- Beta: Most recent beta releases of Homebridge 2.0, and Homebridge UI. And the upcoming version of NodeJS.
- Alpha: Most recent alpha releases of Homebridge, and Homebridge UI. And the upcoming version of NodeJS.

All virtual disk and applicance images are parkaged and available as a github release.  

   - [Stable/Latest](https://github.com/homebridge/homebridge-vm-image/releases/latest)
  
  For the beta and alpha releases, please select the most recent beta or alpha tag
   - [Tags](https://github.com/homebridge/homebridge-vm-image/releases/tag/)

---

## Usage - Virtual Disk Image

1. Download the latest Virtual Disk Images for your CPU Architecture.
2. Create a new virtual machine in HyperV, VirtualBox, Parallels Desktop, ESXi etc.  You must choice the CPU Architecture based on your Host machines's architecture.
    * *OS*: Linux -> Debian -> Debian (64bit) or Debian (ARM 64bit)
    * *Hyper-V*: Select "Generation 1 VM"
3. Configure your virtual machine with the following settings:
    * **RAM**: 4GB Minimum
    * **CPU**: 1+
    * **Network Adapter**: [Bridged Adapter](https://github.com/homebridge/homebridge/wiki/VirtualBox-and-Parallels-Desktop-VM-Network-Settings) (VirtualBox / Parallels Desktop) or [External Switch](https://docs.microsoft.com/en-us/windows-server/virtualization/hyper-v/get-started/create-a-virtual-switch-for-hyper-v-virtual-machines) (Hyper-V).
    * **Existing Virtual Disk Image**: homebridge-vm-image-*.gz (extract first, then this must stay attached forever, so store the .img in a safe place).  Pls use the correct file for your virtual Machine.
        * *VirtualBox*: Do not check the "Is Live CD" box.
4. Start your VM.
5. During first boot in the console window, it will ask you to create a local account for access to the Virtual Machine.  Pls create an account, and remember your credentials.
6. Connect to the address shown in the console window, eg. `http://192.168.1.100:8581`.
7. Manage Homebridge.

## Usage - Microsoft HyperV

1. Download the latest Microsoft HyperV Appliance Image ( **HyperV** ) for your CPU Architecture.
2. Create a new virtual machine in HyperV
   * Hyper-V settings:
   * Generation 2
   * 4096MB memory (dynamic checked)
   * Network - "Default Switch"
   * Use existing virtual HD and pointed to the .vhdx file
   * After created, go to settings for that VM
     * uncheck Enable Secure Boot
     * check Enable Trusted Platform Module
3. Start your VM.
4. During first boot in the console window, it will ask you to create a local account for access to the Virtual Machine.  Pls create an account, and remember your credentials.
5. Connect to the address shown in the console window, eg. `http://192.168.1.100:8581`.
6. Manage Homebridge.

## Usage - Virtual Box Appliance

1. Download the latest Virtual Box Applicance Image (**ova**) for your CPU Architecture:
   - [Stable](https://github.com/homebridge/homebridge-vm-image/releases/tag/2025-10-03)
   - [Beta](https://github.com/homebridge/homebridge-vm-image/releases/tag/beta-2025-10-02)
   - [Alpha](https://github.com/homebridge/homebridge-vm-image/releases/tag/alpha-2025-10-02)

2. Store the Applicance in a safe place.  Pls use the correct file for your virtual Machine.

3. Select `Import Applicance` from the menu. And select the file you downloaded earlier.

4. Start your VM.
5. During first boot in the console window, it will ask you to create a local account for access to the Virtual Machine.  Pls create an account, and remember your credentials.
6. Connect to the address shown in the console window, eg. `http://192.168.1.100:8581`.
7. Manage Homebridge.

## Usage - UTM Applicance

1. Download the latest UTM Applicance Image (**utm**) for your CPU Architecture:
   - [Stable](https://github.com/homebridge/homebridge-vm-image/releases/tag/2025-10-03)
   - [Beta](https://github.com/homebridge/homebridge-vm-image/releases/tag/beta-2025-10-02)
   - [Alpha](https://github.com/homebridge/homebridge-vm-image/releases/tag/alpha-2025-10-02)

2. Unzip and store the Applicance in a safe place.  Pls use the correct file for your virtual Machine.

3. Select `Create a New Virtual Machine` from the menu. And choice `Existing`, then select file you downloaded earlier.

4. Start your VM.
5. During first boot in the console window, it will ask you to create a local account for access to the Virtual Machine.  Pls create an account, and remember your credentials.
6. Connect to the address shown in the console window, eg. `http://192.168.1.100:8581`.
7. Manage Homebridge.

---

# First Boot

During the first boot you will need to create a local user account within the virtual machine to manage the image.  This can used to login to the console and the SSH into the image for any required maintenace. Please keep the credential safe.

<p align="center">
  <img src="assets/First Boot.png">
</p>

Also during first boot on UTM or Virtual Box, the virtual hard disk will be expanded to a 50Gb dynamic virtual hard disk.

# Configuration Reference

[Configuration Reference](https://github.com/homebridge/homebridge/wiki/Install-Homebridge-on-Debian-or-Ubuntu-Linux#configuration-reference)


# Included Scripts

This repository provides a set of scripts to automate building, packaging, validating, and expanding the Homebridge VM images for various platforms and architectures. Below is a summary of the key scripts and their purpose:

---

## Build and Packaging Scripts

convert-img-to-virtual-disk.sh		Dockerfile				local-validate-virtual-box-package.sh	package-for-virtual-box.sh
create-release-body.sh			local-build-in-docker.sh		package-for-utm.sh			validate-utm-package.sh


- **build-debian-image.sh**  
  Main build script for creating the Debian-based Homebridge VM image. Handles disk image creation, OS installation, package setup, and final compression.  Called by Github Action workflows and scripts/local-build-in-docker.sh.

- **local-build-in-docker.sh**  
  Allows running `build-debian-image.sh` script on non-linux MacOS Hosts.

- **package-for-virtual-box.sh**  
  Packages the raw disk image created from `build-debian-image.sh` into a VirtualBox-compatible format (VDI), configures the VM, and exports as an OVA appliance.

- **package-for-utm.sh**  
  Packages the raw disk image created from `build-debian-image.sh` into a UTM bundle, configuring VM settings, and exporting the bundle as a `.utm.tgz` file.

- **create-release-body.sh**
  Creates the body document for the Github Release.

---

## Validation Scripts

- **validate-utm-package.sh**  
  Validates the UTM VM bundle by importing, configuring, starting the VM, and checking that Homebridge is accessible via its web interface.

- **local-validate-virtual-box-package.sh**  
  Validates the VirtualBox VM by starting the VM, checking its state, and verifying Homebridge UI is available.

---

## Image Scripts from assets

- **expandVirtualFilesystem**  
  Expands the root filesystem inside the VM to utilize all available disk space. Typically run on first boot or after disk resize.

- **first-boot-homebridge**  
  Handles initial setup tasks on first boot, including user creation and basic configuration.

---

## Local Builds for Testing

- **UTM**
You can run a local build on MacOS with this command

```bash
./local-build-in-docker.sh && ./package-for-utm.sh
```
- **Virtual Box**
You can run a local build on MacOS with this command

```bash
./local-build-in-docker.sh && ./package-for-virtual-box.sh
```

---
# Troubleshoot VM Boot issues

```
sudo journalctl -b
```

## first-boot-homebridge

```
sudo journalctl -u first-boot-homebridge -b
```

## install-vb-guest-additions

```
sudo journalctl -u install-vb-guest-additions -b
```

# tzupdate

```
sudo journalctl -u tzupdate -b
```

systemd-networkd-wait-online.service

sudo journalctl -u systemd-networkd-wait-online.service -b
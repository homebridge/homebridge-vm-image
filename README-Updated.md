# Homebridge VM Boot Image

A preconfigured Debian Virtual Disk Image for X86 and Arm cpu architecture that runs Homebridge.

The virtual disk is created similar to how the Homebridge Raspbian image is created, and leverages Debian as the Operating System, with NodeJs, Homebridge and the Homebridge UI already installed.

## Virtual Images Available:

| File | Usage |
|:-------:|:-------:|
| OVA | Open Virtual Appliance optimized for VirtualBox |
| UTM | UTM Appliance |
| QCOW2 | QEMU/KVM Virtual Hard Diskt, also leveraged by Virtual Box |
| VDI | Virtual Disk Image |
| VHDX | Microsoft HyperV Virtual Hard Disk |
| VMDK | VMware Virtual Hard Disk |

## Supported CPU Architectures:

| CPU Architecture | Description |
|:-------:|:-------:|
| amd64 | 64 Bit Intel X86 and AMD Cpu's |
| arm64 | 64 Bit Arm CPU's including M based Mac's |

<p align="center">
  <img src="assets/console.png">
</p>

# Virtual Disk Image Specifications

* OS: Debian 12 ( aka `Bookworm` ) Lite
* CPU Architecture: X86/Intel/AMD64 and ARM ( Includes M cpu based Macs )
* Virtual Disk Size: Allocated as a 5Gb Virtual Hard Drive for VDI, VHDX and VMDK and 50Gb for gcow2.  
* Packages Installed: NodeJS, Homebridge, Homebridge UI and ffmpeg.  Exact versions installed are listed in the Manifest file.
* Guest Additions: **UTM** Installed

> **Note**: This VM image uses the official [Homebridge](https://github.com/homebridge/homebridge) packages from the official APT repository. If you were previously using images based on `oznu/homebridge` or from the old [`homebridge-vm-image-boot2docker`](https://github.com/homebridge/homebridge-vm-image-boot2docker) repository (v0.0.4), these new VM images provide the updated official Homebridge distribution.

## Release Streams

Virtual Disk Images are supplied supporting the various Homebridge Release Streams.
- Stable/Latest: Most recent releases of NodeJS, Homebridge, Homebridge UI, and FFMPEG
- Beta: Most recent beta releases of Homebridge, and Homebridge UI. And the upcoming version of NodeJS.
- Alpha: Most recent beta releases of Homebridge, and Homebridge UI. And the upcoming version of NodeJS.

## Usage - Virtual Disk Image

1. Click here to download the latest Virtual Disk Images for your CPU Architecture:
   - [Stable](https://github.com/homebridge/homebridge-vm-image/releases/tag/2025-10-03)
   - [Beta](https://github.com/homebridge/homebridge-vm-image/releases/tag/beta-2025-10-02)
   - [Alpha](https://github.com/homebridge/homebridge-vm-image/releases/tag/alpha-2025-10-02)
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

## Usage - Virtual Box Appliance

1. Click here to download the latest Virtual Box Applicance Image (**ova**) for your CPU Architecture:
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

1. Click here to download the latest UTM Applicance Image (**utm**) for your CPU Architecture:
   - [Stable](https://github.com/homebridge/homebridge-vm-image/releases/tag/2025-10-03)
   - [Beta](https://github.com/homebridge/homebridge-vm-image/releases/tag/beta-2025-10-02)
   - [Alpha](https://github.com/homebridge/homebridge-vm-image/releases/tag/alpha-2025-10-02)

2. Unzip and store the Applicance in a safe place.  Pls use the correct file for your virtual Machine.

3. Select `Create a New Virtual Machine` from the menu. And choice `Existing`, then select file you downloaded earlier.

4. Start your VM.
5. During first boot in the console window, it will ask you to create a local account for access to the Virtual Machine.  Pls create an account, and remember your credentials.
6. Connect to the address shown in the console window, eg. `http://192.168.1.100:8581`.
7. Manage Homebridge.


<p align="center">
  <img src="assets/First Boot.png">
</p>

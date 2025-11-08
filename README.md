# Homebridge VM Image

A preconfigured Debian Virtual Disk Image for x86 and ARM CPU architectures that runs Homebridge.

Recommended for use on non-Linux based systems where Docker cannot be used, such as Windows or macOS.

The virtual disk is created similar to how the Homebridge Raspbian image is created, and leverages Debian as the operating system, with Node.js, Homebridge, and the Homebridge UI already installed.

<p align="center">
  <img src="assets/Console.png">
</p>

## Documentation

**For installation instructions, system requirements, and usage guides, please visit the [Homebridge VM Image Wiki](https://github.com/homebridge/homebridge/wiki/Install-Homebridge-on-Virtual-Machine).**

The wiki includes:
- Detailed installation instructions for all platforms (Hyper-V, VirtualBox, UTM, QEMU/KVM)
- CPU architecture and system requirements
- First boot setup guide
- Virtual disk specifications
- Release stream information (Stable, Beta, Alpha)
- Configuration reference
- Troubleshooting guides

## Available Formats

### Appliance Images (Ready to Import)
- **OVA** - VirtualBox Open Virtual Appliance
- **UTM** - UTM Appliance for macOS
- **HyperV** - Microsoft Hyper-V Virtual Machine (Windows 10/11 Enterprise, Pro, or Education)

### Virtual Disk Images (Manual Setup)
- **QCOW2** - QEMU/KVM Virtual Hard Disk
- **VDI** - Virtual Disk Image (VirtualBox)
- **VHDX** - Microsoft Hyper-V Virtual Hard Disk
- **VMDK** - VMware Virtual Hard Disk

### Supported CPU Architectures
- **amd64** - 64-bit Intel/AMD processors
- **arm64** - 64-bit ARM processors (including Apple Silicon Macs)

## Release Streams

| Stream | Node.js | Homebridge | UI | FFmpeg | Best For |
|--------|---------|------------|-----|--------|----------|
| **Stable** | LTS | Latest | Latest | Latest | Production use |
| **Beta** | Current | Beta V2 | Beta | Latest | Testing new features |
| **Alpha** | Current | Alpha | Alpha | Latest | Experimental/development |

---

## Developer Documentation

The following sections are intended for developers and contributors working on the Homebridge VM Image build system.

### Repository Structure

```
homebridge-vm-image/
├── scripts/              # Build and packaging automation scripts
├── assets/               # VM configuration files and first-boot scripts.  These were mostly copied from homebridge-raspbian-image with a few minor tweaks.
├── .github/workflows/    # CI/CD GitHub Actions workflows
└── README.md            # This file
```

### Build and Packaging Scripts

#### Main Build Scripts

- **`build-debian-image.sh`**  
  Main build script for creating the Debian-based Homebridge VM image. Handles disk image creation, OS installation, package setup, and final compression. Called by GitHub Action workflows and `scripts/local-build-in-docker.sh`.

- **`scripts/local-build-in-docker.sh`**  
  Allows running the `build-debian-image.sh` script on non-Linux macOS hosts using Docker.

#### Platform-Specific Packaging

- **`scripts/package-for-virtual-box.sh`**  
  Packages the raw disk image into a VirtualBox-compatible format (VDI), configures the VM, and exports as an OVA appliance.

- **`scripts/package-for-utm.sh`**  
  Packages the raw disk image into a UTM bundle, configures VM settings, and exports as a `.utm.tgz` file.

- **`scripts/create-release-body.sh`**  
  Generates the release notes document for GitHub releases.

#### Validation Scripts

- **`scripts/validate-utm-package.sh`**  
  Validates the UTM VM bundle by importing, configuring, starting the VM, and verifying Homebridge accessibility.

- **`scripts/local-validate-virtual-box-package.sh`**  
  Validates the VirtualBox VM by starting it and checking that Homebridge UI is available.

### VM Image Scripts

These scripts are included in the VM image and run during first boot or maintenance:

- **`/usr/local/sbin/first-boot-homebridge`**  
  Handles initial setup tasks on first boot, including local user account creation and basic configuration.

- **`/usr/local/sbin/expandVirtualFilesystem`**  
  Expands the root filesystem to utilize all allocated disk space. Runs during first boot and can be re-run if virtual disk allocation changes. Tested with UTM and VirtualBox.

- **`/usr/local/sbin/updateIssueVMName`**  
  Updates `/etc/issue` to include VM software name. Runs during first boot.

### Local Development Builds

#### UTM (macOS)
```bash
./local-build-in-docker.sh && ./package-for-utm.sh
```

#### VirtualBox (macOS)
```bash
./local-build-in-docker.sh && ./package-for-virtual-box.sh
```

### Release Workflow

The automated release process consists of four stages:

#### Stage 1: Update Dependencies (`release-stage-1_update_dependencies`)

**Trigger:** Daily cron job

**Steps:**
1. Runs `homebridge-dependency-bot` to check for upstream dependency updates
2. Iterates through each release stream (stable, beta, alpha)
3. Creates and merges PRs for dependency updates
4. Triggers Stage 2 for each architecture that needs updating

#### Stage 2: Build and Push Images (`release-stage-2_build_and_push_images`)

**Inputs:**
- Release Stream (stable, beta, or alpha)

**Steps:**
1. Runs `build-debian-image.sh` to create Debian virtual hard disk images with Homebridge pre-installed
2. Creates images for each architecture (amd64, arm64)
3. Attaches created images as artifacts to the job

**Triggers:** Stage 3

**Note:** This workflow can be manually re-run at any time.

#### Stage 3: Package Release (`release-stage-3_package_release`)

**Inputs:**
- GitHub Run ID from Stage 2
- Release Stream
- GitHub Release tag

**Steps:**
1. Creates a GitHub pre-release with the specified tag
2. Runs `scripts/convert-img-to-virtual-disk.sh` to convert images to various VM formats
3. Runs `scripts/create-release-body.sh` to generate release notes
4. Uploads converted images to GitHub release

**Triggers:**
- Stage 4 appliance workflows
- Cleanup workflow for old beta/alpha releases

**Note:** To re-run, delete the existing release first.

#### Stage 4: Package for VM (`release-stage-4_package-for-VM`)

**Inputs:**
- GitHub Run ID from Stage 2
- Release Stream
- GitHub Release tag

**Steps:**
1. Creates VM appliances for Hyper-V, VirtualBox, and UTM
   - VirtualBox: Uses `scripts/package-for-virtual-box.sh`
   - UTM: Uses `scripts/package-for-utm.sh`
   - Hyper-V: Uses PowerShell commands
2. Uploads appliances to GitHub release

**Note:** This workflow can be re-run and will overwrite existing appliances.

### Troubleshooting VM Boot Issues

#### View All Boot Messages
```bash
sudo journalctl -b
```

#### Check First Boot Service
```bash
sudo journalctl -u first-boot-homebridge -b
```

#### Check VirtualBox Guest Additions Installation
```bash
sudo journalctl -u install-vb-guest-additions -b
```

#### Check Timezone Update Service
```bash
sudo journalctl -u tzupdate -b
```

---

## Contributing

Contributions are welcome! Please ensure:
- All changes are tested thoroughly before submitting PRs
- Build scripts maintain compatibility with both amd64 and arm64 architectures
- Documentation is updated to reflect any changes
- Follow existing code style and conventions

## Support

- **Issues:** [GitHub Issues](https://github.com/homebridge/homebridge-vm-image/issues)
- **Wiki:** [Installation and Usage Documentation](https://github.com/homebridge/homebridge-vm-image/wiki)
- **Discord:** [Homebridge Community](https://discord.gg/homebridge)

## License

This project is licensed under the Apache-2.0 License - see the LICENSE file for details.
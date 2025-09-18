# Homebridge VM Boot Image Builder

A VM image builder that creates minimal bootable Linux images with Homebridge pre-installed for AMD64 and ARM64 architectures.

Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.

## Working Effectively

### Build Requirements and Setup
- Install required system packages:
  ```bash
  sudo apt-get update
  sudo apt-get install -y \
    debootstrap parted e2fsprogs dosfstools \
    grub-pc-bin grub-efi-amd64-bin \
    qemu-user-static gzip
  ```

### Building VM Images
- **CRITICAL**: Always run with appropriate timeout values. Set timeout to 60+ minutes for build commands.
- Make build script executable: `chmod +x ./build.sh`
- Build for AMD64: `sudo ./build.sh amd64` -- takes 3-5 minutes normally. NEVER CANCEL. Set timeout to 30+ minutes.
- Build for ARM64: `sudo ./build.sh arm64` -- takes 25-30 minutes normally. NEVER CANCEL. Set timeout to 60+ minutes.
- **IMPORTANT**: The build requires network connectivity in chroot environment for downloading Homebridge packages. If build fails with "Could not resolve host: repo.homebridge.io", this indicates DNS resolution issues in the chroot. This typically works in GitHub Actions but may fail in restricted environments.

### Build Process Details
The build script (`build.sh`) performs these steps:
1. Creates a 3GB disk image with GPT partition table (EFI System Partition + ext4 root)
2. Uses debootstrap to install Debian bookworm base system
3. Installs Linux kernel, GRUB EFI bootloader, and system packages
4. Adds official Homebridge APT repository and installs Homebridge
5. Configures services (homebridge, avahi-daemon) for auto-start
6. Installs fallback EFI bootloader for maximum VM compatibility
7. Compresses final image with gzip

### Validation and Testing
- **Cannot run or test the VM images directly** in this environment - they are designed for virtual machine hypervisors
- Validate build success by checking for final output: `✅ Finished: output/homebridge-{arch}.img.gz`
- Check output file exists: `ls -la output/`
- Verify compressed image size is reasonable (typically 400-800MB compressed)

### Manual Cleanup (if build fails)
If a build fails and leaves mounted filesystems or loop devices:
```bash
sudo fuser -km work-{arch}/rootfs/dev || true
sudo fuser -km work-{arch}/rootfs/proc || true  
sudo fuser -km work-{arch}/rootfs/sys || true
sudo umount -l work-{arch}/rootfs/proc || true
sudo umount -l work-{arch}/rootfs/sys || true
sudo umount -l work-{arch}/rootfs/dev || true
sudo umount -l work-{arch}/rootfs/boot/efi || true
sudo umount -l work-{arch}/rootfs || true
sudo umount -l work-{arch}/esp || true
sudo losetup -d /dev/loop0 || true  # or appropriate loop device
sudo rm -rf work-{arch} output || true
```

## Repository Structure

### Key Files and Directories
```
├── .github/
│   └── workflows/
│       └── build.yml          # GitHub Actions CI/CD pipeline
├── assets/
│   ├── 50-avahi.service       # Avahi service configuration for Homebridge discovery
│   ├── cloud-init.yaml        # Cloud-init configuration (unused in current build)
│   └── homebridge.service     # Systemd service file for Homebridge
├── build.sh                   # Main build script
├── README.md                  # Usage documentation for end users
└── LICENSE                    # Apache 2.0 license
```

### GitHub Actions Workflow
- Triggered on: push to main/beta branches, tags (v*), or manual workflow dispatch
- Builds both AMD64 and ARM64 images in parallel
- Uploads compressed images to GitHub Releases automatically on tags or manual runs
- Uses ubuntu-latest runners with QEMU setup for cross-architecture builds

## Common Tasks

### Modifying the Build Process
- **Build script**: Edit `build.sh` for changes to the image creation process
- **Homebridge service**: Modify `assets/homebridge.service` for service configuration changes
- **Avahi discovery**: Edit `assets/50-avahi.service` for network discovery settings

### Asset Files Details
- `50-avahi.service`: Enables Homebridge discovery on port 51826 via mDNS/Bonjour
- `homebridge.service`: Runs Homebridge as user "homebridge" in `/var/lib/homebridge`
- `cloud-init.yaml`: Alternative cloud-init configuration (not used by current build process)

### Disk Space Requirements
- Requires approximately 8GB free disk space for build process
- Working directory (`work-{arch}/`) uses ~4GB during build
- Final compressed images are typically 400-800MB

### Architecture Support
- **AMD64/x86_64**: Standard Intel/AMD processors, fastest build time (~3-5 minutes)
- **ARM64/AArch64**: ARM processors (Apple Silicon, AWS Graviton, etc.), longer build time (~25-30 minutes due to QEMU emulation)

## Troubleshooting

### Common Issues
- **DNS resolution failures**: Network connectivity issues in chroot environment - typically works in CI but may fail locally
- **Loop device busy**: Use manual cleanup commands if build interrupted
- **Insufficient disk space**: Ensure at least 8GB free space before building
- **Permission denied**: All build commands require sudo privileges

### Build Time Expectations
- **NEVER CANCEL builds** - they may appear to hang but are processing
- AMD64: 3-5 minutes typical, allow up to 30 minutes timeout
- ARM64: 25-30 minutes typical, allow up to 60 minutes timeout
- Compression step: Additional 1-2 minutes after main build completes

### Validation Checks
Always verify after making changes:
1. Build script is executable: `test -x ./build.sh && echo "OK" || echo "FAIL"`
2. Required packages installed: `dpkg -l | grep -E "debootstrap|parted|grub-efi"`
3. Sufficient disk space: `df -h . | grep -v "^Filesystem"`
4. Clean working directory: `ls work-* 2>/dev/null || echo "Clean"`

## CI/CD Integration
- Builds automatically trigger on version tags (`v*`)
- Manual builds via GitHub Actions workflow dispatch
- Artifacts uploaded to GitHub Releases automatically
- No additional validation steps required - successful build indicates working image
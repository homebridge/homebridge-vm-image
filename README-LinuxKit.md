# LinuxKit-based Homebridge VM Image Builder

This directory contains a LinuxKit-based implementation for creating Homebridge VM images. LinuxKit provides a modern, container-based approach to building minimal, immutable Linux distributions.

## Overview

LinuxKit creates lightweight, secure, and portable Linux subsystems. This implementation leverages LinuxKit to build VM images containing Homebridge with all necessary dependencies in an immutable, container-based environment.

## Benefits of LinuxKit approach

- **Container-based**: Each service runs in its own container for better isolation
- **Immutable**: The base OS is read-only, improving security and reliability
- **Lightweight**: Minimal footprint with only necessary components
- **Cross-platform**: Build on macOS, Linux, and Windows with Docker
- **Multiple output formats**: Raw, VMDK, QCOW2, and ISO formats

## Prerequisites

- **Docker Desktop**: Required for building images
- **LinuxKit**: Will be installed automatically by the build script
- **qemu-img**: Optional, for VMDK format creation (install via `qemu-utils` on Ubuntu/Debian)
- **VirtualBox**: Required for validation (validation script only)

### Installation on macOS/M1

1. Install Docker Desktop from https://www.docker.com/products/docker-desktop/
2. Ensure Docker is running
3. Run the build script - LinuxKit will be installed automatically

## Files

- `homebridge-linuxkit.yml` - LinuxKit configuration for Homebridge
- `build-linuxkit.sh` - Build script (macOS/M1 and Linux compatible)
- `validate-linuxkit.sh` - VirtualBox validation script

## Building Images

### Basic Usage

```bash
# Build for host architecture (auto-detected)
./build-linuxkit.sh

# Build for specific architecture
./build-linuxkit.sh amd64
./build-linuxkit.sh arm64

# Get help
./build-linuxkit.sh --help
```

**Auto-Detection**: The script automatically detects your host architecture:
- **Apple Silicon (M1/M2/M3)**: Defaults to ARM64 build for optimal compatibility
- **Intel Mac/PC**: Defaults to AMD64 build

### Output Formats

The build creates multiple formats suitable for different hypervisors:

- **homebridge-{arch}-efi.img** - EFI-bootable raw disk image (modern systems, mountable on macOS)
- **homebridge-{arch}.img.gz** - Compressed raw disk image for distribution
- **homebridge-{arch}.vmdk** - VMware disk format (created using qemu-img if available)
- **homebridge-{arch}-efi.qcow2** - QEMU/KVM disk format with EFI support

**Note**: 
- The build focuses on EFI format for modern hypervisors and best compatibility
- EFI format works with VirtualBox (enable EFI in VM settings), VMware, and modern hypervisors
- IMG files are mountable on macOS using DiskImageMounter for inspection
- VMDK format is created using `qemu-img` (auto-installed on macOS via Homebrew)
- For legacy BIOS compatibility, use VirtualBox's compatibility mode or other formats

### Build Time

- **AMD64**: ~5-10 minutes (depending on network and Docker cache)
- **ARM64**: ~5-15 minutes (faster than traditional cross-compilation)

## Validating Images

Use the validation script to test built images with VirtualBox:

```bash
# Validate AMD64 image
./validate-linuxkit.sh amd64

# Validate ARM64 image  
./validate-linuxkit.sh arm64

# Get help
./validate-linuxkit.sh --help
```

### Validation Process

The validation script:
1. Creates a VirtualBox VM with appropriate settings
2. Starts the VM in headless mode
3. Waits for Homebridge services to start
4. Tests HTTP connectivity to Homebridge UI (port 8581)
5. Tests HomeKit service availability (port 51826)
6. Reports validation results
7. Leaves VM running for re-testing or manual inspection

**Note**: The VM is left running after successful validation to allow for re-testing and manual inspection. Use the cleanup script when done.

## Cleanup

### Cleanup Script

Use `cleanup-linuxkit.sh` to remove VMs and temporary files:

```bash
# Clean up current architecture VM (auto-detected)
./cleanup-linuxkit.sh

# Clean up specific architecture VM
./cleanup-linuxkit.sh amd64
./cleanup-linuxkit.sh arm64

# Clean up all LinuxKit test VMs
./cleanup-linuxkit.sh all

# Get help
./cleanup-linuxkit.sh --help
```

### What the Cleanup Script Does

- Stops any running LinuxKit test VMs gracefully
- Removes VM configurations from VirtualBox completely
- Cleans up temporary files (converted VMDK files, etc.)
- Provides confirmation before removing multiple VMs

### Manual VM Management

If you prefer manual control:

```bash
# Start VM in GUI mode
VBoxManage startvm "homebridge-linuxkit-test" --type gui

# Stop VM gracefully
VBoxManage controlvm "homebridge-linuxkit-test" acpipowerbutton

# Remove VM completely
VBoxManage unregistervm "homebridge-linuxkit-test" --delete
```

## LinuxKit Configuration

The `homebridge-linuxkit.yml` file defines:

- **Kernel**: Linux 6.6.71 with console output
- **Init system**: LinuxKit init, runc, and containerd
- **Networking**: DHCP client for automatic IP assignment
- **Services**:
  - **Getty**: Console access with insecure mode for development
  - **Homebridge**: Alpine 3.18 with Node.js, Homebridge and Config UI X (avoids Docker Hub rate limits)
  - **Avahi**: mDNS/Bonjour for HomeKit discovery
- **Files**: Avahi service configuration for HomeKit advertising

## macOS Integration

- **DiskImageMounter**: The `.img` files are raw disk images that can be mounted on macOS using DiskImageMounter for inspection
- **Apple Silicon (M1/M2) Compatibility**: 
  - **VirtualBox**: Only supports ARM64 VMs on Apple Silicon - use `./build-linuxkit.sh arm64`
  - **VMware Fusion**: Supports both ARM64 natively and x86 emulation
  - **Parallels Desktop**: Supports both ARM64 natively and x86 emulation  
  - **UTM**: Supports both ARM64 natively and x86 emulation
- **Intel Mac Compatibility**:
  - **VirtualBox**: Supports both AMD64 and ARM64 VMs
  - **VMware Fusion**: Supports both AMD64 and ARM64 VMs
  - **Parallels Desktop**: Supports both AMD64 and ARM64 VMs

## Architecture Support

- **AMD64/x86_64**: Full support with fast builds
- **ARM64/AArch64**: Full support, ideal for Apple Silicon Macs

## Hypervisor Compatibility

### VirtualBox
- Use the `.vmdk` file or convert `.img.gz` to `.vdi`
- EFI firmware required
- Bridged or NAT networking

### VMware (Desktop/Fusion/Workstation)
- Use the `.vmdk` file directly
- EFI firmware recommended

### QEMU/KVM
- Use the `.qcow2` file
- EFI firmware (OVMF) required

### Hyper-V
- Convert `.img` to `.vhdx` using `qemu-img`
- Generation 2 VM required

## Default Configuration

The built images include:

- **Homebridge UI**: http://VM_IP:8581
- **HomeKit Bridge**: Port 51826
- **Default PIN**: 031-45-154
- **Bridge Name**: Homebridge
- **MAC Address**: CC:22:3D:E3:CE:30
- **VirtualBox Guest Additions**: Pre-installed for enhanced VM integration
  - Bidirectional clipboard sharing
  - Drag and drop support
  - Better graphics performance
  - Seamless mouse integration

## Customization

To customize the Homebridge configuration:

1. Edit `homebridge-linuxkit.yml`
2. Modify the JSON config in the homebridge service command
3. Rebuild the image

## Troubleshooting

### Build Issues

- **Docker not running**: Start Docker Desktop
- **LinuxKit not found**: Will be installed automatically
- **Permission denied**: Ensure Docker can run without sudo (macOS/Linux)
- **Docker Hub rate limits**: The configuration uses `alpine:3.18` base image and avoids `--pull` flag to minimize rate limit issues
- **VMDK creation failed**: 
  - **macOS**: qemu will be installed automatically via Homebrew if available
  - **Linux**: Install qemu-utils package manually
  ```bash
  # Ubuntu/Debian
  sudo apt-get install qemu-utils
  
  # RHEL/CentOS/Fedora
  sudo yum install qemu-img
  
  # Alpine
  apk add qemu-img
  ```

### VM Boot Issues

- **VM stops at GRUB**: Enable EFI firmware in VM settings for EFI images, or use legacy BIOS mode in hypervisor settings
- **VM won't start**: Ensure EFI firmware is enabled for EFI images in VM settings
- **LinuxKitISO Image error**: Use the disk image formats (.img, .vmdk) instead of ISO; LinuxKit creates disk images, not bootable ISOs
- **Network not working**: Use bridged networking for best results
- **Services not starting**: Check VM has at least 1GB RAM and give it time to fully boot (2-3 minutes)
- **Legacy BIOS needed**: Use VirtualBox's compatibility mode or configure hypervisor for BIOS boot with EFI images

### Validation Issues

- **VirtualBox not found**: Install VirtualBox from https://www.virtualbox.org/
- **VM creation fails**: Ensure no existing VM with the same name
- **Architecture mismatch**: VirtualBox on Apple Silicon (M1/M2) cannot run AMD64/x86 VMs
  - Use ARM64 builds on Apple Silicon: `./build-linuxkit.sh arm64` and `./validate-linuxkit.sh arm64`
  - For x86 emulation on Apple Silicon, use UTM or Parallels Desktop instead of VirtualBox
- **Image not found**: The validation script supports multiple formats (VMDK, compressed IMG, RAW, EFI IMG) and will auto-convert as needed. Ensure the build completed successfully and produced at least one supported format.
- **Timeout during validation**: Increase timeout or check VM console

## Development

### Building Custom Images

1. Modify `homebridge-linuxkit.yml` as needed
2. Test with `linuxkit build --dry-run homebridge-linuxkit.yml`
3. Build with `./build-linuxkit.sh`
4. Validate with `./validate-linuxkit.sh`

### Adding Services

LinuxKit services can be added to the `services` section of the YAML file. Each service runs in its own container.

### Security Considerations

- The default configuration includes insecure getty for development
- For production use, disable insecure getty and enable proper authentication
- Consider adding SSH keys or other authentication methods

## Comparison with Traditional Build

| Aspect | Traditional (build.sh) | LinuxKit |
|--------|------------------------|----------|
| Base OS | Debian bootstrap | Container-based |
| Build deps | debootstrap, parted | Docker, LinuxKit |
| Cross-arch | QEMU emulation (slow) | Native Docker (fast) |
| Formats | Raw IMG | Raw, VMDK, QCOW2, ISO |
| Portability | Linux hosts only | macOS, Linux, Windows |
| Security | Traditional package mgmt | Immutable, containerized |
| Size | ~3GB raw | ~1GB raw |

## Known Limitations

- Requires Docker Desktop (not podman or other runtimes)
- ARM64 validation requires VirtualBox 7.0+ with ARM64 support
- Some hypervisors may require additional configuration for EFI boot

## VirtualBox Guest Additions

The LinuxKit images come with VirtualBox Guest Additions pre-installed and configured for enhanced VM integration:

### Features Available

- **Bidirectional Clipboard**: Copy/paste between host and guest OS
- **Drag & Drop**: File transfer via drag and drop (bidirectional)
- **Seamless Mouse Integration**: No mouse capture/release needed
- **Better Graphics Performance**: Optimized display drivers
- **Automatic Resolution Adjustment**: VM screen adapts to window size

### Auto-Configuration

The validation script automatically configures:
- Bidirectional clipboard sharing
- Bidirectional drag and drop
- VMSVGA graphics controller for optimal performance

### Manual Configuration

If using the image outside the validation script, enable these features in VirtualBox:

1. **Shared Clipboard**: VM Settings → General → Advanced → Shared Clipboard → Bidirectional
2. **Drag & Drop**: VM Settings → General → Advanced → Drag'n'Drop → Bidirectional
3. **Graphics**: VM Settings → Display → Graphics Controller → VMSVGA

## Future Enhancements

- Add SSH server configuration
- Support for cloud-init
- Custom Homebridge plugin installation
- Multi-stage builds for smaller images
- ARM64 native validation on Apple Silicon
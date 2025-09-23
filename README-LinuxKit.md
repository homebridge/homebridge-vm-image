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
# Build for AMD64 (default)
./build-linuxkit.sh

# Build for specific architecture
./build-linuxkit.sh amd64
./build-linuxkit.sh arm64

# Get help
./build-linuxkit.sh --help
```

### Output Formats

The build creates multiple formats suitable for different hypervisors:

- **homebridge-{arch}.img.gz** - Compressed raw disk image (universal compatibility)
- **homebridge-{arch}.vmdk** - VMware disk format
- **homebridge-{arch}.qcow2** - QEMU/KVM disk format

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

## LinuxKit Configuration

The `homebridge-linuxkit.yml` file defines:

- **Kernel**: Linux 6.6.71 with console output
- **Init system**: LinuxKit init, runc, and containerd
- **Networking**: DHCP client for automatic IP assignment
- **Services**:
  - **Getty**: Console access with insecure mode for development
  - **Homebridge**: Node.js 18 with Homebridge and Config UI X
  - **Avahi**: mDNS/Bonjour for HomeKit discovery
- **Files**: Avahi service configuration for HomeKit advertising

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

### VM Boot Issues

- **VM won't start**: Ensure EFI firmware is enabled
- **Network not working**: Use bridged networking for best results
- **Services not starting**: Check VM has at least 1GB RAM

### Validation Issues

- **VirtualBox not found**: Install VirtualBox from https://www.virtualbox.org/
- **VM creation fails**: Ensure no existing VM with the same name
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

## Future Enhancements

- Add SSH server configuration
- Support for cloud-init
- Custom Homebridge plugin installation
- Multi-stage builds for smaller images
- ARM64 native validation on Apple Silicon
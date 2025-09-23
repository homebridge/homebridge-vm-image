# VirtualBox ARM64 Support for Homebridge VM

This document provides guidance for using Homebridge VM images with VirtualBox on ARM64 systems.

## Current Status

VirtualBox ARM64 support is **experimental** as of 2024. This repository includes workflows and tools to create and validate VirtualBox-compatible VM images for ARM64 systems, but users should be aware of limitations.

## Requirements

### Software Requirements
- **VirtualBox 7.0+** with ARM64 support
- **ARM64 host system** (Apple Silicon Mac, Windows ARM64, Linux ARM64)
- **Minimum 2GB RAM** available for the VM
- **8GB free disk space** for VM storage

### Supported Platforms

| Platform | VirtualBox Support | Recommended Alternative |
|----------|-------------------|------------------------|
| **macOS ARM64** (Apple Silicon) | Experimental in VBox 7.0+ | UTM or Parallels Desktop |
| **Windows ARM64** | Limited support | Hyper-V |
| **Linux ARM64** | Varies by distribution | QEMU/KVM |

## Installation & Usage

### 1. Download VirtualBox-Optimized Image

```bash
# Download the ARM64 VirtualBox-optimized image
wget https://github.com/homebridge/homebridge-vm-image/releases/latest/download/homebridge-arm64-vbox.img.gz

# Extract the image
gunzip homebridge-arm64-vbox.img.gz
```

### 2. Create VM using Automated Script

```bash
# Use the included VM creation script
chmod +x create-homebridge-vm.sh
./create-homebridge-vm.sh
```

### 3. Manual VM Creation

1. **Create New VM**
   - Name: `Homebridge-ARM64`
   - Type: `Linux`
   - Version: `Other Linux (64-bit)`
   - Memory: `1024 MB` (minimum) or `2048 MB` (recommended)

2. **Configure VM Settings**
   - **System**: Enable I/O APIC, disable EFI
   - **Processor**: 2+ CPUs if available
   - **Storage**: Attach `homebridge-arm64-vbox.img` as SATA disk
   - **Network**: Bridged Adapter (for direct network access)

3. **Port Forwarding** (if using NAT)
   - Host `8581` → Guest `8581` (Homebridge Web UI)
   - Host `2222` → Guest `22` (SSH access)

## Validation & Testing

### Automated Validation

```powershell
# Run ARM64 VirtualBox validation
.\validate-vm-vbox-arm64.ps1 -ImagePath "homebridge-arm64-vbox.img.gz"

# Skip service validation (basic bootstrap test only)
.\validate-vm-vbox-arm64.ps1 -SkipValidation
```

### Manual Testing

1. **Start the VM**
   ```bash
   VBoxManage startvm "Homebridge-ARM64" --type headless
   ```

2. **Check VM Status**
   ```bash
   VBoxManage showvminfo "Homebridge-ARM64" --details
   ```

3. **Monitor Console**
   ```bash
   # Console output is logged to vm-console.log
   tail -f vm-console.log
   ```

## Known Limitations

### VirtualBox ARM64 Limitations
- **Performance**: May be slower than native virtualization
- **Stability**: Experimental support, may have crashes
- **Features**: Some VirtualBox features may not work on ARM64
- **Guest Additions**: Limited ARM64 guest additions support

### Platform-Specific Issues

#### macOS ARM64 (Apple Silicon)
- VirtualBox 7.0+ required for any ARM64 support
- Performance significantly lower than UTM or Parallels
- Some macOS versions may have compatibility issues

#### Windows ARM64
- VirtualBox ARM64 support very limited
- Hyper-V is strongly recommended instead
- Installation may require Windows Insider builds

#### Linux ARM64
- Support varies by distribution
- QEMU/KVM generally provides better performance
- May require custom kernel modules

## Troubleshooting

### Common Issues

#### VM Won't Start
```bash
# Check VirtualBox version supports ARM64
VBoxManage --version

# Verify VM configuration
VBoxManage showvminfo "Homebridge-ARM64"

# Check for error messages
VBoxManage startvm "Homebridge-ARM64" --type headless
```

#### Poor Performance
- **Increase VM RAM**: Try 2048MB instead of 1024MB
- **Enable Hardware Acceleration**: If available on your platform
- **Reduce VM CPU count**: Sometimes 1 CPU performs better than 2
- **Consider alternatives**: UTM (macOS) or Hyper-V (Windows)

#### Network Issues
- **Use Bridged Adapter**: Provides direct network access
- **Check Port Forwarding**: Ensure 8581 is forwarded correctly
- **Firewall Settings**: Verify host firewall allows VM traffic

### Getting Help

1. **Check Validation Report**
   ```powershell
   # Review validation output
   Get-Content vbox-arm64-validation-results.json
   ```

2. **Collect Logs**
   - VirtualBox logs: `~/VirtualBox VMs/Homebridge-ARM64/Logs/`
   - VM console: `vm-console.log`
   - Validation report: `vbox-arm64-validation-results.json`

3. **Try Alternatives**
   - macOS: [UTM](https://mac.getutm.app/) or [Parallels Desktop](https://www.parallels.com/)
   - Windows: [Hyper-V](https://docs.microsoft.com/en-us/virtualization/hyper-v-on-windows/)
   - Linux: [QEMU/KVM](https://www.qemu.org/)

## Contributing

If you encounter issues or have improvements for VirtualBox ARM64 support:

1. **Report Issues**: Use GitHub Issues with ARM64 label
2. **Submit PRs**: Improvements to ARM64 validation scripts welcome
3. **Test Results**: Share validation results from different ARM64 platforms

## Alternative Virtualization Options

While this repository provides VirtualBox ARM64 support, consider these alternatives for better ARM64 performance:

### macOS ARM64
- **UTM**: Native ARM64 virtualization, excellent performance
- **Parallels Desktop**: Commercial but highly optimized
- **VMware Fusion**: ARM64 support in newer versions

### Windows ARM64
- **Hyper-V**: Native Windows virtualization
- **VMware Workstation Pro**: Check for ARM64 support

### Linux ARM64
- **QEMU/KVM**: Excellent performance with KVM acceleration
- **libvirt**: Management layer for QEMU/KVM
- **Docker**: Container-based alternative

## License

This VirtualBox ARM64 support is provided under the same license as the main Homebridge VM Image project.
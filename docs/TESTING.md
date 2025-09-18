# VM Image Validation Testing

This document explains how to test the VM image validation system using actual VM platforms.

## Overview

The validation system consists of two main components:

1. **`validate-vm.ps1`** - A PowerShell script that boots VM images using VirtualBox and validates that Homebridge starts correctly
2. **`.github/workflows/validate.yml`** - A GitHub Actions workflow that runs the validation on Windows runners using VirtualBox

## What Gets Validated

The validation process checks:

- ✅ VM image boots properly in VirtualBox
- ✅ Homebridge service starts automatically
- ✅ Homebridge web interface is accessible on port 8581
- ✅ Web interface responds with valid Homebridge content

## Supported VM Platforms

### GitHub Actions (Automated)
- **VirtualBox** on Windows runners (primary platform for CI/CD)

### Manual Testing (Local)
- **VirtualBox** (Windows, macOS, Linux)
- **Hyper-V** (Windows Pro/Enterprise) 
- **Parallels Desktop** (macOS)
- **VMware** (Windows, macOS, Linux)

## Manual Testing

### Prerequisites

For VirtualBox testing, you need:

**Windows:**
```powershell
# Download and install VirtualBox from https://www.virtualbox.org/
# Or using Chocolatey:
choco install virtualbox
```

**macOS:**
```bash
# Using Homebrew:
brew install --cask virtualbox
```

**Linux:**
```bash
# Ubuntu/Debian:
sudo apt-get install virtualbox

# Or download from https://www.virtualbox.org/
```

### Running Manual Tests

1. Build a VM image (or download from releases):
   ```bash
   # On Linux/WSL:
   chmod +x build.sh
   sudo ./build.sh amd64
   ```

2. Run the validation script:
   ```powershell
   # Windows PowerShell:
   .\validate-vm.ps1 -Architecture amd64 -ImagePath "output\homebridge-amd64.img.gz"
   ```

3. The script will:
   - Extract the VM image
   - Create a VirtualBox VM with appropriate settings
   - Start the VM and wait for boot (up to 5 minutes)
   - Test HTTP connectivity to port 8581
   - Verify the response looks like Homebridge
   - Clean up the VM automatically

### Expected Output

Successful validation looks like:
```
🚀 Starting VM validation for amd64 architecture...
📁 Image: output\homebridge-amd64.img.gz
⏱️ Timeout: 300s
✅ VirtualBox version: 7.0.20r163906
📦 Extracting compressed image...
🖥️ Creating VirtualBox VM...
💾 Attaching disk image...
▶️ Starting VM...
⏳ Waiting for VM to boot and services to start...
⏳ Still waiting... (15s/300s)
⏳ Still waiting... (20s/300s)
✅ VM booted successfully and Homebridge web interface is accessible!
🔍 Validating Homebridge web interface...
✅ Homebridge web interface responded successfully!
✅ Response appears to be from Homebridge application
🎉 VM image validation completed successfully for amd64!
✅ VM boots properly
✅ Homebridge service starts
✅ Web interface accessible on port 8581
```

## Automated Testing (GitHub Actions)

The workflow runs automatically on:
- Push to `main` or `beta` branches
- Pull requests to `main` 
- Manual trigger via `workflow_dispatch`

### Workflow Behavior

1. **Windows Runner**: The workflow runs on `windows-latest` runners to support actual VM platforms.

2. **VirtualBox Installation**: Automatically installs VirtualBox on the runner.

3. **Image Download**: The workflow tries to download VM images from the latest release. Building images in CI is not currently supported due to the complexity of setting up Linux build tools on Windows.

4. **VM Platform Testing**: Uses VirtualBox to create and boot actual VMs, testing the real user experience.

5. **Architecture Support**: Currently supports AMD64/x86_64 only, as ARM64 VMs are not well-supported on GitHub Actions Windows runners.

6. **Validation**: Each image runs through the complete validation process with a 15-minute timeout to account for VM startup time.

7. **Artifact Collection**: If validation fails, console logs and debugging information are uploaded as artifacts.

## Platform-Specific Testing

### VirtualBox (Primary CI Platform)
- **Supported Architectures**: AMD64/x86_64
- **Features**: Headless operation, serial console logging, port forwarding
- **Advantages**: Free, cross-platform, well-supported in CI environments

### Hyper-V (Windows Only)
For local Hyper-V testing:
```powershell
# Enable Hyper-V (requires Windows Pro/Enterprise)
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All

# Create VM manually and attach the .img file
# Set up NAT networking to access web interface
```

### Parallels Desktop (macOS Only)
For local Parallels testing:
1. Create new VM with "Other Linux" as OS type
2. Attach the extracted .img file as boot disk
3. Configure bridged networking
4. Start VM and connect to web interface

### VMware (Cross-Platform)
For local VMware testing:
1. Create new VM with Linux guest OS
2. Attach .img file as existing hard disk
3. Configure network adapter for host access
4. Power on and test connectivity

## Troubleshooting

### Common Issues

1. **VM doesn't boot within timeout**
   - Check if VM image is corrupted
   - Increase timeout value (`-Timeout` parameter)
   - Check available system resources (RAM, CPU)
   - Review VM console logs

2. **VirtualBox not found**
   - Install VirtualBox from https://www.virtualbox.org/
   - Ensure VBoxManage is in system PATH
   - Check VirtualBox service is running

3. **Network connectivity issues**
   - Ensure ports 2222 and 8581 are available on host
   - Check Windows Firewall settings
   - Verify VirtualBox NAT configuration

4. **Homebridge service not starting**
   - Review VM console output (`vm-console.log`)
   - Check if services are enabled in the image build
   - Verify VM has sufficient RAM (minimum 1GB)

5. **Image extraction failures**
   - Ensure 7-Zip is installed (usually available on Windows runners)
   - Check if .gz file is corrupted
   - Verify sufficient disk space

### Debugging

For detailed debugging, you can:

1. **Enable PowerShell debug output:**
   ```powershell
   $DebugPreference = "Continue"
   .\validate-vm.ps1 -Architecture amd64 -ImagePath "image.img.gz"
   ```

2. **Check VirtualBox logs:**
   ```powershell
   # List VMs
   VBoxManage list vms
   
   # Get VM info
   VBoxManage showvminfo "VM-NAME" --details
   
   # Check VM logs
   VBoxManage showvminfo "VM-NAME" --log 0
   ```

3. **Review console output:**
   - Console logs are saved to `vm-console.log` during validation
   - Check GitHub Actions logs for detailed output

4. **Manual VM testing:**
   - Create VM manually in VirtualBox GUI
   - Attach the .img file and boot interactively
   - Connect to console to debug boot issues

## Architecture Support

The validation system supports:
- **AMD64/x86_64**: Full support with VirtualBox on Windows runners
- **ARM64/AArch64**: Not currently supported in GitHub Actions due to platform limitations

For ARM64 testing, manual validation using supported platforms like:
- Apple Silicon Macs with Parallels Desktop or VMware Fusion
- ARM64 Windows devices with Hyper-V
- ARM64 Linux systems with KVM/QEMU
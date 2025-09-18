# VM Image Validation Testing

This document explains how to test the VM image validation system.

## Overview

The validation system consists of two main components:

1. **`validate-vm.sh`** - A shell script that boots VM images using QEMU and validates that Homebridge starts correctly
2. **`.github/workflows/validate.yml`** - A GitHub Actions workflow that runs the validation for both architectures

## What Gets Validated

The validation process checks:

- ✅ VM image boots properly
- ✅ Homebridge service starts automatically
- ✅ Homebridge web interface is accessible on port 8581
- ✅ Web interface responds with valid Homebridge content

## Manual Testing

### Prerequisites

You need QEMU installed for the target architecture:

```bash
# For Ubuntu/Debian
sudo apt-get install qemu-system-x86 qemu-system-arm qemu-utils

# For macOS with Homebrew
brew install qemu
```

### Running Manual Tests

1. Build a VM image (or download from releases):
   ```bash
   chmod +x build.sh
   sudo ./build.sh amd64  # or arm64
   ```

2. Run the validation script:
   ```bash
   chmod +x validate-vm.sh
   ./validate-vm.sh amd64 output/homebridge-amd64.img.gz
   ```

3. The script will:
   - Extract the VM image
   - Start QEMU with appropriate settings
   - Wait for the VM to boot (up to 5 minutes)
   - Test HTTP connectivity to port 8581
   - Verify the response looks like Homebridge

### Expected Output

Successful validation looks like:
```
🚀 Starting VM validation for amd64 architecture...
📁 Image: output/homebridge-amd64.img.gz
⏱️ Timeout: 300s
📦 Extracting compressed image...
🖥️ Starting QEMU VM...
🔧 VM started with PID: 12345
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

1. **Download or Build**: The workflow first tries to download VM images from the latest release. If none exist, it builds them using the build script.

2. **Parallel Testing**: Both AMD64 and ARM64 architectures are tested in parallel for faster feedback.

3. **Environment Setup**: The workflow installs QEMU and all required dependencies automatically.

4. **Validation**: Each architecture runs through the complete validation process with a 10-minute timeout.

5. **Artifact Collection**: If validation fails, logs and debugging information are uploaded as artifacts.

## Troubleshooting

### Common Issues

1. **VM doesn't boot within timeout**
   - Check if VM image is corrupted
   - Increase timeout value (3rd parameter to validate-vm.sh)
   - Check available system resources

2. **QEMU not found**
   - Install QEMU for the target architecture
   - Ensure qemu-system-x86_64 or qemu-system-aarch64 are in PATH

3. **Network connectivity issues**
   - Ensure ports 2222 and 8581 are available
   - Check firewall settings

4. **Homebridge service not starting**
   - Review VM serial console output
   - Check if services are enabled in the image build

### Debugging

For detailed debugging, you can:

1. Run the validation script with bash debug mode:
   ```bash
   bash -x ./validate-vm.sh amd64 image.img.gz
   ```

2. Connect to the VM console (remove -daemonize from QEMU command in script)

3. Check GitHub Actions logs for detailed output

## Architecture Support

The validation system supports:
- **AMD64/x86_64**: Uses qemu-system-x86_64 with KVM acceleration when available
- **ARM64/AArch64**: Uses qemu-system-aarch64 with Cortex-A57 emulation

Both architectures are tested to ensure cross-platform compatibility of the VM images.
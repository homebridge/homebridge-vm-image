# VM Validation Scripts

This directory contains validation scripts for testing the Homebridge VM images on different platforms.

## Available Scripts

### macOS Validation Script
**File:** `validate-vm-macos.sh`

Validates the Homebridge VM image on macOS using VirtualBox.

**Usage:**
```bash
chmod +x validate-vm-macos.sh
./validate-vm-macos.sh [architecture]
```

**Arguments:**
- `architecture`: `amd64` or `arm64` (default: `amd64`)

**Requirements:**
- macOS
- Homebrew (script will use it to install VirtualBox and utilities)
- Internet connection

**What it does:**
1. Installs VirtualBox via Homebrew if not present
2. Downloads the latest Homebridge VM image release
3. Installs required utilities (curl, gzip, jq)
4. Configures and starts the VM with proper network settings
5. Validates that Homebridge service starts correctly
6. Tests web interface accessibility on port 8581
7. Checks SSH port accessibility on port 2222
8. Cleans up the VM after validation

**Example:**
```bash
# Validate AMD64 image
./validate-vm-macos.sh amd64

# Validate ARM64 image (for Apple Silicon Macs)
./validate-vm-macos.sh arm64
```

**Expected Output:**
- VM boots successfully
- Homebridge web interface becomes accessible at http://localhost:8581
- SSH port 2222 becomes accessible (if SSH server is enabled in VM)

### Windows PowerShell Scripts

The following PowerShell scripts are available for Windows validation:

- `validate-vm-simple.ps1` - Simple VirtualBox validation for Windows
- `validate-vm-hyperv.ps1` - Hyper-V validation for Windows
- `VirtualBox-Manager.ps1` - VirtualBox management functions
- `HyperV-Manager.ps1` - Hyper-V management functions
- `Homebridge-Validator.ps1` - Homebridge service validation functions
- `Common-Functions.ps1` - Shared utility functions

## SSH-based Validation

The issue requested SSH-based validation using these commands:
- `sudo hb-service status`
- `sudo hb-service view`

**Current Status:** 
The macOS script checks for SSH port accessibility but cannot execute these commands because:
1. The VM image doesn't currently include an SSH server
2. No default credentials are configured

**To enable full SSH validation:**
1. Add `openssh-server` to the VM image build process in `build.sh`
2. Configure default credentials (e.g., homebridge:homebridge)
3. Enable SSH service on boot

Once SSH is enabled, you can manually test with:
```bash
ssh -p 2222 homebridge@localhost 'sudo hb-service status'
ssh -p 2222 homebridge@localhost 'sudo hb-service view'
```

## Troubleshooting

### VirtualBox Installation Issues
If VirtualBox installation fails, try:
```bash
# Install Homebrew if not present
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install VirtualBox manually
brew install --cask virtualbox
```

### VM Boot Issues
- Ensure you have enough available RAM (at least 1GB free)
- Check that VT-x/AMD-V virtualization is enabled in BIOS
- Verify the downloaded image file isn't corrupted

### Network Issues
- Check firewall settings aren't blocking ports 8581 or 2222
- Ensure no other services are using these ports

## Logs and Output

Each validation run creates:
- `validation-YYYYMMDD-HHMMSS.log` - Detailed execution log
- `validation-results.json` - JSON summary of results
- `vm-screenshot.png` - VM screenshot if validation fails
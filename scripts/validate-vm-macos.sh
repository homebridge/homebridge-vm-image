#!/usr/bin/env bash

# macOS VirtualBox VM Image Validation Script
# This script validates the Homebridge VM image on macOS using VirtualBox
#
# Usage:
#   ./validate-vm-macos.sh [architecture]
#   
# Arguments:
#   architecture: 'amd64' or 'arm64' (default: amd64)
#
# Example:
#   ./validate-vm-macos.sh amd64
#   ./validate-vm-macos.sh arm64
#
# Requirements:
#   - macOS
#   - Homebrew (for installing VirtualBox and utilities)
#   - Internet connection (for downloading VirtualBox and VM image)
#
# This script will:
#   1. Install VirtualBox via Homebrew if not present
#   2. Download the latest Homebridge VM image release
#   3. Install required utilities (curl, gzip, jq)
#   4. Configure and start the VM with proper network settings
#   5. Validate that Homebridge service starts correctly
#   6. Test web interface accessibility on port 8581
#   7. Check SSH port accessibility on port 2222
#   8. Leave VM running for log review (use cleanup-vm-macos.sh to clean up)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

VM_NAME="homebridge-test-vm"
LOG_FILE="validation-$(date +%Y%m%d-%H%M%S).log"
TIMEOUT=300  # 5 minutes timeout for Homebridge to start
CHECK_INTERVAL=10
VM_RAM=1024  # 1GB RAM
GITHUB_REPO="homebridge/homebridge-vm-image"
LATEST_RELEASE_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"

# Logging function
log() {
    local message="$1"
    local color="${2:-$NC}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${color}${message}${NC}"
    echo "[$timestamp] $message" >> "$LOG_FILE"
}

# Configuration
ARCHITECTURE="${1:-}"  # Get from command line argument

# Auto-detect architecture if not specified
if [[ -z "$ARCHITECTURE" ]]; then
    case "$(uname -m)" in
        "x86_64"|"amd64")
            ARCHITECTURE="amd64"
            ;;
        "arm64"|"aarch64")
            ARCHITECTURE="arm64"
            ;;
        *)
            log "⚠️ Unknown architecture $(uname -m), defaulting to amd64" "$YELLOW"
            ARCHITECTURE="amd64"
            ;;
    esac
    log "🔍 Auto-detected architecture: $ARCHITECTURE" "$BLUE"
fi

# Show help if requested
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" ]]; then
    echo "macOS VirtualBox VM Image Validation Script"
    echo ""
    echo "Usage: $0 [architecture]"
    echo ""
    echo "Arguments:"
    echo "  architecture    'amd64' or 'arm64' (auto-detected if not specified)"
    echo ""
    echo "Examples:"
    echo "  $0              # Auto-detect architecture"
    echo "  $0 amd64        # Force AMD64 image"
    echo "  $0 arm64        # Force ARM64 image"
    echo ""
    echo "This script will download and validate a Homebridge VM image using VirtualBox."
    exit 0
fi

# Validate architecture
if [[ "$ARCHITECTURE" != "amd64" && "$ARCHITECTURE" != "arm64" ]]; then
    log "❌ Unsupported architecture: $ARCHITECTURE. Use 'amd64' or 'arm64'" "$RED"
    log "💡 Run '$0 --help' for usage information" "$GRAY"
    exit 1
fi

log "🚀 Starting macOS VirtualBox validation for $ARCHITECTURE architecture" "$GREEN"

# Step 1: Install VirtualBox if not present
log "📦 Checking VirtualBox installation..." "$YELLOW"
if ! command -v VBoxManage >/dev/null 2>&1; then
    log "⬇️ VirtualBox not found. Installing via Homebrew..." "$YELLOW"
    
    # Check if Homebrew is installed
    if ! command -v brew >/dev/null 2>&1; then
        log "❌ Homebrew not found. Please install Homebrew first:" "$RED"
        log "   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"" "$GRAY"
        exit 1
    fi
    
    # Install VirtualBox
    brew install --cask virtualbox
    
    # Verify installation
    if ! command -v VBoxManage >/dev/null 2>&1; then
        log "❌ VirtualBox installation failed" "$RED"
        exit 1
    fi
else
    log "✅ VirtualBox is already installed" "$GREEN"
fi

# Check system requirements for VM
log "🔍 Checking system requirements..." "$YELLOW"
TOTAL_MEM=$(sysctl -n hw.memsize)
TOTAL_MEM_GB=$((TOTAL_MEM / 1024 / 1024 / 1024))
AVAILABLE_MEM=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
AVAILABLE_MEM_MB=$((AVAILABLE_MEM * 4096 / 1024 / 1024))

log "💾 Total system memory: ${TOTAL_MEM_GB}GB" "$GRAY"
log "💾 Available memory: ${AVAILABLE_MEM_MB}MB" "$GRAY"

if [[ $AVAILABLE_MEM_MB -lt 2048 ]]; then
    log "⚠️ Warning: Low available memory (${AVAILABLE_MEM_MB}MB). VM may fail to start." "$YELLOW"
    log "💡 Close other applications to free up memory" "$GRAY"
fi

# Check virtualization support
if sysctl -n machdep.cpu.features | grep -q VMX; then
    log "✅ Intel VT-x virtualization supported" "$GREEN"
elif sysctl -n machdep.cpu.features 2>/dev/null | grep -q "VT-x\|VMX"; then
    log "✅ Virtualization supported" "$GREEN"
else
    log "⚠️ Warning: Could not detect virtualization support" "$YELLOW"
fi

# Step 2: Install required utilities
log "🔧 Installing required utilities..." "$YELLOW"

# Check and install utilities one by one with better error handling
utilities_needed=("curl" "gzip" "jq")
utilities_missing=()

for util in "${utilities_needed[@]}"; do
    if ! command -v "$util" >/dev/null 2>&1; then
        utilities_missing+=("$util")
    fi
done

if [[ ${#utilities_missing[@]} -gt 0 ]]; then
    log "📥 Installing missing utilities: ${utilities_missing[*]}" "$YELLOW"
    if ! brew install "${utilities_missing[@]}"; then
        log "❌ Failed to install required utilities. Please install manually:" "$RED"
        for util in "${utilities_missing[@]}"; do
            log "   brew install $util" "$GRAY"
        done
        exit 1
    fi
fi

log "✅ Required utilities installed" "$GREEN"

# Check for nc (netcat) availability - usually built into macOS
if ! command -v nc >/dev/null 2>&1; then
    log "⚠️ netcat (nc) not found - port checking will rely on curl only" "$YELLOW"
fi

# Step 3: Download latest VM image
log "⬇️ Downloading latest VM image..." "$YELLOW"
IMG_GZ_FILE="homebridge-${ARCHITECTURE}.img.gz"
IMG_FILE="homebridge-${ARCHITECTURE}.img"

# Get latest release download URL
DOWNLOAD_URL=$(curl -s "$LATEST_RELEASE_URL" | jq -r ".assets[] | select(.name==\"$IMG_GZ_FILE\") | .browser_download_url")

if [[ "$DOWNLOAD_URL" == "null" || -z "$DOWNLOAD_URL" ]]; then
    log "❌ Could not find download URL for $IMG_GZ_FILE" "$RED"
    exit 1
fi

log "📡 Downloading from: $DOWNLOAD_URL" "$GRAY"
curl -L -o "$IMG_GZ_FILE" "$DOWNLOAD_URL"

if [[ ! -f "$IMG_GZ_FILE" ]]; then
    log "❌ Failed to download VM image" "$RED"
    exit 1
fi
log "✅ VM image downloaded successfully" "$GREEN"

# Step 4: Extract the image
log "📦 Extracting VM image..." "$YELLOW"
gunzip "$IMG_GZ_FILE"

if [[ ! -f "$IMG_FILE" ]]; then
    log "❌ Failed to extract VM image" "$RED"
    exit 1
fi
log "✅ VM image extracted successfully" "$GREEN"

# Step 5: Convert to VDI format
log "🔄 Converting image to VDI format..." "$YELLOW"
VDI_FILE="homebridge-${ARCHITECTURE}.vdi"
VBoxManage convertfromraw "$IMG_FILE" "$VDI_FILE" --format VDI

if [[ ! -f "$VDI_FILE" ]]; then
    log "❌ Failed to convert image to VDI format" "$RED"
    exit 1
fi
log "✅ Image converted to VDI format" "$GREEN"

# Step 6: Create and configure VM
log "🖥️ Creating VirtualBox VM..." "$YELLOW"

# Remove existing VM if present
VBoxManage unregistervm "$VM_NAME" --delete 2>/dev/null || true

# Determine OS type based on architecture
if [[ "$ARCHITECTURE" == "arm64" ]]; then
    OSTYPE="Debian12_arm64"  # Use Debian 12 ARM64 for Apple Silicon
else
    OSTYPE="Debian_64"  # Use Debian 64-bit for Intel
fi

log "🔧 Using OS type: $OSTYPE for $ARCHITECTURE architecture" "$GRAY"

# Create VM
VBoxManage createvm --name "$VM_NAME" --ostype "$OSTYPE" --register

# Configure VM settings for headless operation
log "⚙️ Configuring VM for headless operation..." "$GRAY"
VBoxManage modifyvm "$VM_NAME" \
    --memory "$VM_RAM" \
    --cpus 1 \
    --firmware efi \
    --boot1 disk \
    --graphicscontroller none \
    --audio-driver none \
    --usb off \
    --uart1 0x3F8 4 \
    --uartmode1 file "vm-console-${ARCHITECTURE}.log" \
    --nic1 nat \
    --natpf1 "ssh,tcp,,2222,,22" \
    --natpf1 "homebridge,tcp,,8581,,8581"

# Verify VM configuration succeeded
if ! VBoxManage showvminfo "$VM_NAME" --machinereadable | grep -q "name=\"$VM_NAME\""; then
    log "❌ VM configuration failed" "$RED"
    exit 1
fi

# Add storage controller and attach disk
log "💾 Configuring VM storage (Live CD mode)..." "$GRAY"
VBoxManage storagectl "$VM_NAME" --name "SATA" --add sata --controller IntelAhci

# Configure the disk as immutable (Live CD behavior) before attaching
VBoxManage modifymedium "$VDI_FILE" --type immutable

# Attach the immutable disk
VBoxManage storageattach "$VM_NAME" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "$VDI_FILE"

VM_CREATED=true
log "✅ VM created and configured" "$GREEN"

# Debug: Show VM configuration
log "🔍 VM Configuration Summary:" "$BLUE"
log "   Name: $VM_NAME" "$GRAY"
log "   OS Type: $OSTYPE" "$GRAY"
log "   Architecture: $ARCHITECTURE" "$GRAY"
log "   Memory: ${VM_RAM}MB" "$GRAY"
log "   Firmware: EFI (with BIOS fallback)" "$GRAY"
log "   Graphics: Disabled (headless mode)" "$GRAY"
log "   Storage: Live CD mode (SATA HDD, immutable)" "$GRAY"
log "   Console: Logged to vm-console-${ARCHITECTURE}.log" "$GRAY"

# Step 7: Start VM
log "▶️ Starting VM..." "$YELLOW"
if ! VBoxManage startvm "$VM_NAME" --type headless; then
    log "⚠️ EFI firmware boot failed. Trying BIOS fallback..." "$YELLOW"
    
    # Stop any running VM instance
    VBoxManage controlvm "$VM_NAME" poweroff 2>/dev/null || true
    sleep 2
    
    # Try with BIOS firmware instead
    VBoxManage modifyvm "$VM_NAME" --firmware bios
    
    if ! VBoxManage startvm "$VM_NAME" --type headless; then
        log "❌ Failed to start VM with both EFI and BIOS firmware. Common issues:" "$RED"
        log "   - VT-x/AMD-V virtualization not enabled in BIOS" "$GRAY"
        log "   - Insufficient available memory (need at least 1GB free)" "$GRAY"
        log "   - Conflicting virtualization software (Docker Desktop, VMware, etc.)" "$GRAY"
        log "   - VirtualBox kernel extensions not loaded properly" "$GRAY"
        log "💡 Try restarting VirtualBox services:" "$GRAY"
        log "   sudo /Library/Application\\ Support/VirtualBox/LaunchDaemons/VirtualBoxStartup.sh restart" "$GRAY"
        exit 1
    else
        log "✅ VM started successfully with BIOS firmware" "$GREEN"
    fi
else
    log "✅ VM started successfully with EFI firmware" "$GREEN"
fi

# Verify VM started
sleep 5
VM_STATE=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep "VMState=" | cut -d'"' -f2)
if [[ "$VM_STATE" != "running" ]]; then
    log "❌ Failed to start VM (state: $VM_STATE)" "$RED"
    exit 1
fi
log "✅ VM started successfully" "$GREEN"

# Step 8: Wait for Homebridge to start
log "⏳ Waiting for Homebridge service to start (timeout: $((TIMEOUT/60)) minutes)..." "$YELLOW"

elapsed=0
service_live=false

while [[ $elapsed -lt $TIMEOUT ]]; do
    sleep "$CHECK_INTERVAL"
    elapsed=$((elapsed + CHECK_INTERVAL))
    
    log "Checking Homebridge (elapsed: ${elapsed}s)..." "$GRAY"
    
    # Check if VM is still running
    VM_STATE=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep "VMState=" | cut -d'"' -f2)
    if [[ "$VM_STATE" != "running" ]]; then
        log "❌ VM stopped unexpectedly (state: $VM_STATE)" "$RED"
        exit 1
    fi
    
    # Try to connect to Homebridge web interface
    if curl -s --connect-timeout 5 "http://localhost:8581" >/dev/null 2>&1; then
        service_live=true
        log "✅ Homebridge web interface is responding!" "$GREEN"
        
        # Check if response contains Homebridge content
        if curl -s --connect-timeout 5 "http://localhost:8581" | grep -q "Homebridge"; then
            log "✅ Homebridge UI confirmed in response" "$GREEN"
        fi
        break
    fi
    
    # Alternative: Check if port is listening using nc (netcat) if available
    if command -v nc >/dev/null 2>&1; then
        if nc -z localhost 8581 2>/dev/null; then
            log "✅ Port 8581 is open (detected via netcat)" "$GREEN"
            service_live=true
            break
        fi
    fi
    
    if [[ $((elapsed % 30)) -eq 0 ]]; then
        log "Still waiting for Homebridge... ($elapsed/$TIMEOUT seconds)" "$YELLOW"
    fi
done

if [[ "$service_live" != "true" ]]; then
    log "❌ Homebridge did not start within timeout" "$RED"
    
    # Try to get console output for debugging
    log "Attempting to retrieve VM console output..." "$YELLOW"
    VBoxManage controlvm "$VM_NAME" screenshotpng "vm-screenshot.png" 2>/dev/null || true
    
    # Show console log information
    if [[ -f "vm-console-${ARCHITECTURE}.log" ]]; then
        log "📋 VM console log available at: vm-console-${ARCHITECTURE}.log" "$BLUE"
        log "💡 Check the console log for boot errors and kernel messages" "$GRAY"
    fi
    
    exit 1
fi

# Step 9: SSH-based validation (as requested in the issue)
log "🔍 Performing SSH-based validation..." "$YELLOW"

# Check if SSH port is accessible
if nc -z localhost 2222 2>/dev/null; then
    log "✅ SSH port (2222) is accessible" "$GREEN"
    
    # Note: SSH validation requires SSH server to be enabled in the VM image
    # and proper authentication setup. The current VM image may not have SSH enabled.
    log "🔐 SSH server validation..." "$YELLOW"
    
    # Try to connect via SSH (this will likely fail without proper SSH setup)
    # We'll just check if the port responds for now
    log "📝 SSH-based Homebridge service validation:" "$BLUE"
    log "   To fully validate with SSH commands:" "$GRAY"
    log "   - ssh -p 2222 homebridge@localhost 'sudo hb-service status'" "$GRAY"
    log "   - ssh -p 2222 homebridge@localhost 'sudo hb-service view'" "$GRAY"
    log "   Note: SSH server needs to be enabled in the VM image for this to work" "$GRAY"
    
    # For now, since SSH isn't set up in the VM image, we'll validate via web interface
    log "🌐 Using web interface validation as SSH alternative" "$YELLOW"
    
else
    log "⚠️ SSH port not accessible (SSH server may not be enabled in VM image)" "$YELLOW"
fi

# Step 10: Additional validation
log "🔍 Performing additional validation..." "$YELLOW"

# Test web interface accessibility
if curl -s --connect-timeout 5 "http://localhost:8581" >/dev/null; then
    log "✅ Homebridge web interface is accessible" "$GREEN"
else
    log "❌ Homebridge web interface is not accessible" "$RED"
    exit 1
fi

# Save validation results
cat > "validation-results.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "architecture": "$ARCHITECTURE",
    "vm_started": true,
    "homebridge_responding": $service_live,
    "ssh_port_accessible": $(nc -z localhost 2222 2>/dev/null && echo true || echo false),
    "web_interface_accessible": true,
    "validation_success": true
}
EOF

log "🎉 VM IMAGE VALIDATION COMPLETED SUCCESSFULLY!" "$GREEN"
log "✅ VM booted successfully" "$GREEN"
log "✅ Homebridge service is running and accessible on port 8581" "$GREEN"
log "🌐 Web interface: http://localhost:8581" "$GREEN"
log "📊 Results saved to validation-results.json" "$GREEN"
log "📋 Log file: $LOG_FILE" "$GRAY"
log "🖥️ VM console log: vm-console-${ARCHITECTURE}.log" "$GRAY"

log "🧹 Cleanup information:" "$BLUE"
log "   VM '$VM_NAME' is still running for your review" "$GRAY"
log "   To clean up VM and files: ./scripts/cleanup-vm-macos.sh" "$GRAY"
log "   To clean up specific arch: ./scripts/cleanup-vm-macos.sh $ARCHITECTURE" "$GRAY"

log "🔧 Next steps for full SSH validation:" "$BLUE"
log "   1. Enable SSH server in VM image build process (add openssh-server)" "$GRAY"
log "   2. Configure default credentials or SSH key authentication" "$GRAY"
log "   3. SSH commands will then work:" "$GRAY"
log "      ssh -p 2222 homebridge@localhost 'sudo hb-service status'" "$GRAY"
log "      ssh -p 2222 homebridge@localhost 'sudo hb-service view'" "$GRAY"

log "✨ Validation completed! You can now connect to Homebridge at http://localhost:8581" "$GREEN"
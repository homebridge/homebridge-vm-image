#!/usr/bin/env bash
set -euo pipefail

# LinuxKit-based VM Image Builder for Homebridge
# Compatible with macOS/M1 and Linux systems
# Requires: Docker, LinuxKit

OUTPUT_DIR="output"
BUILD_DIR="build"
LINUXKIT_CONFIG="homebridge-linuxkit.yml"

# Handle help flag first
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  print_usage() {
    echo "Usage: $0 [ARCHITECTURE]"
    echo ""
    echo "Build Homebridge VM images using LinuxKit"
    echo ""
    echo "Arguments:"
    echo "  ARCHITECTURE    Target architecture (amd64|arm64) [default: amd64]"
    echo ""
    echo "Examples:"
    echo "  $0              # Build for amd64"
    echo "  $0 amd64        # Build for amd64"
    echo "  $0 arm64        # Build for ARM64"
    echo ""
    echo "Requirements:"
    echo "  - Docker Desktop"
    echo "  - LinuxKit (will be installed automatically)"
    echo ""
    echo "Output formats:"
    echo "  - RAW/IMG format (compressed) - for VirtualBox, VMware, etc."
    echo "  - VMDK format - for VMware"
    echo "  - QCOW2 format - for QEMU/KVM"
  }
  print_usage
  exit 0
fi

ARCH="${1:-amd64}"

# Validate architecture
if [[ "$ARCH" != "arm64" && "$ARCH" != "amd64" ]]; then
  echo "❌ Unsupported architecture: $ARCH"
  echo "Supported architectures: amd64, arm64"
  exit 1
fi

# Check dependencies
check_dependencies() {
  echo "🔍 Checking dependencies..."
  
  # Check Docker
  if ! command -v docker &> /dev/null; then
    echo "❌ Docker is required but not installed"
    echo "Please install Docker Desktop: https://www.docker.com/products/docker-desktop/"
    exit 1
  fi
  
  # Check if Docker is running
  if ! docker info &> /dev/null; then
    echo "❌ Docker is not running"
    echo "Please start Docker Desktop"
    exit 1
  fi
  
  # Check LinuxKit
  if ! command -v linuxkit &> /dev/null; then
    echo "📥 LinuxKit not found, installing..."
    install_linuxkit
  fi
  
  echo "✅ All dependencies are available"
}

install_linuxkit() {
  local os
  local arch_suffix
  
  # Detect OS
  case "$(uname -s)" in
    Darwin*) os="darwin" ;;
    Linux*) os="linux" ;;
    *) 
      echo "❌ Unsupported OS: $(uname -s)"
      exit 1
      ;;
  esac
  
  # Detect architecture
  case "$(uname -m)" in
    x86_64) arch_suffix="amd64" ;;
    arm64|aarch64) arch_suffix="arm64" ;;
    *)
      echo "❌ Unsupported architecture: $(uname -m)"
      exit 1
      ;;
  esac
  
  echo "📥 Installing LinuxKit for $os-$arch_suffix..."
  
  local linuxkit_version="v1.2.0"
  local download_url="https://github.com/linuxkit/linuxkit/releases/download/${linuxkit_version}/linuxkit-${os}-${arch_suffix}"
  
  # Create local bin directory if it doesn't exist
  mkdir -p ~/.local/bin
  
  # Download LinuxKit
  if command -v curl &> /dev/null; then
    curl -L -o ~/.local/bin/linuxkit "$download_url"
  elif command -v wget &> /dev/null; then
    wget -O ~/.local/bin/linuxkit "$download_url"
  else
    echo "❌ Neither curl nor wget found. Please install one of them."
    exit 1
  fi
  
  chmod +x ~/.local/bin/linuxkit
  
  # Add to PATH if not already there
  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> ~/.bashrc
    echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> ~/.zshrc 2>/dev/null || true
    export PATH="$HOME/.local/bin:$PATH"
  fi
  
  echo "✅ LinuxKit installed to ~/.local/bin/linuxkit"
  echo "💡 You may need to restart your shell or run: export PATH=\"\$HOME/.local/bin:\$PATH\""
}

build_image() {
  echo "🚀 Building Homebridge VM image for $ARCH architecture..."
  
  # Clean and create directories
  rm -rf "$OUTPUT_DIR" "$BUILD_DIR"
  mkdir -p "$OUTPUT_DIR" "$BUILD_DIR"
  
  # Check if config file exists
  if [[ ! -f "$LINUXKIT_CONFIG" ]]; then
    echo "❌ LinuxKit configuration file not found: $LINUXKIT_CONFIG"
    exit 1
  fi
  
  echo "📋 Using LinuxKit configuration: $LINUXKIT_CONFIG"
  echo "🏗️  Building for architecture: $ARCH"
  
  # Build with LinuxKit
  local image_name="homebridge-$ARCH"
  
  echo "🔨 Running LinuxKit build..."
  linuxkit build \
    --arch "$ARCH" \
    --format raw-efi \
    --format vmdk \
    --format qcow2-efi \
    --name "$image_name" \
    --dir "$OUTPUT_DIR" \
    --pull \
    "$LINUXKIT_CONFIG"
  
  # Check if build was successful
  if [[ -f "$OUTPUT_DIR/$image_name.raw" ]]; then
    echo "✅ Raw image created: $OUTPUT_DIR/$image_name.raw"
    
    # Convert to IMG format for compatibility
    echo "🔄 Converting to IMG format..."
    cp "$OUTPUT_DIR/$image_name.raw" "$OUTPUT_DIR/$image_name.img"
    
    # Compress the image
    echo "📦 Compressing image..."
    gzip -f "$OUTPUT_DIR/$image_name.img"
    
    echo "✅ Compressed image: $OUTPUT_DIR/$image_name.img.gz"
  fi
  
  if [[ -f "$OUTPUT_DIR/$image_name.vmdk" ]]; then
    echo "✅ VMDK image created: $OUTPUT_DIR/$image_name.vmdk"
  fi
  
  if [[ -f "$OUTPUT_DIR/$image_name-efi.iso" ]]; then
    echo "✅ EFI ISO created: $OUTPUT_DIR/$image_name-efi.iso"
  fi
  
  if [[ -f "$OUTPUT_DIR/$image_name.qcow2" ]]; then
    echo "✅ QCOW2 image created: $OUTPUT_DIR/$image_name.qcow2"
  fi
  
  echo ""
  echo "🎉 Build completed successfully!"
  echo "📁 Output files are in: $OUTPUT_DIR/"
  ls -lh "$OUTPUT_DIR/"
}

print_usage() {
  echo "Usage: $0 [ARCHITECTURE]"
  echo ""
  echo "Build Homebridge VM images using LinuxKit"
  echo ""
  echo "Arguments:"
  echo "  ARCHITECTURE    Target architecture (amd64|arm64) [default: amd64]"
  echo ""
  echo "Examples:"
  echo "  $0              # Build for amd64"
  echo "  $0 amd64        # Build for amd64"
  echo "  $0 arm64        # Build for ARM64"
  echo ""
  echo "Requirements:"
  echo "  - Docker Desktop"
  echo "  - LinuxKit (will be installed automatically)"
  echo ""
  echo "Output formats:"
  echo "  - RAW/IMG format (compressed) - for VirtualBox, VMware, etc."
  echo "  - VMDK format - for VMware"
  echo "  - QCOW2 format - for QEMU/KVM"
}

main() {
  echo "🏠 Homebridge LinuxKit VM Image Builder"
  echo "======================================="
  
  check_dependencies
  build_image
  
  echo ""
  echo "✨ Next steps:"
  echo "1. Use validate-linuxkit.sh to test the VM"
  echo "2. Import the VM image into your hypervisor:"
  echo "   - VirtualBox: Use the .vmdk or converted .vdi file"
  echo "   - VMware: Use the .vmdk file"
  echo "   - QEMU/KVM: Use the .qcow2 file"
  echo "3. Configure VM with 1GB+ RAM and boot from the image"
  echo "4. Access Homebridge at http://VM_IP:8581"
}

main "$@"
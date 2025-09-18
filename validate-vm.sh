#!/usr/bin/env bash
set -euo pipefail

# VM Image Validation Script
# Tests that the VM image boots properly and Homebridge starts correctly

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <arch> [img_path] [timeout] [vm_ram]"
  echo "  arch: amd64 or arm64"
  echo "  img_path: path to VM image (default: output/homebridge-\${arch}.img.gz)"
  echo "  timeout: boot timeout in seconds (default: 300)"
  echo "  vm_ram: VM RAM in MB (default: 1024)"
  exit 1
fi

ARCH="$1"
IMG_PATH="${2:-output/homebridge-${ARCH}.img.gz}"
TIMEOUT="${3:-300}"  # 5 minutes timeout
VM_RAM="${4:-1024}"  # 1GB RAM
SSH_PORT="2222"
HTTP_PORT="8581"

if [[ "$ARCH" != "arm64" && "$ARCH" != "amd64" ]]; then
  echo "❌ Unsupported architecture: $ARCH"
  exit 1
fi

if [[ ! -f "$IMG_PATH" ]]; then
  echo "❌ VM image not found: $IMG_PATH"
  exit 1
fi

echo "🚀 Starting VM validation for $ARCH architecture..."
echo "📁 Image: $IMG_PATH"
echo "⏱️ Timeout: ${TIMEOUT}s"

# Extract image if compressed
WORK_IMG="$(mktemp -d)/homebridge-${ARCH}-test.img"
if [[ "$IMG_PATH" == *.gz ]]; then
  echo "📦 Extracting compressed image..."
  gunzip -c "$IMG_PATH" > "$WORK_IMG"
else
  cp "$IMG_PATH" "$WORK_IMG"
fi

# Set QEMU executable based on architecture
if [[ "$ARCH" == "amd64" ]]; then
  QEMU_CMD="qemu-system-x86_64"
  # Check if KVM is available, otherwise use fallback
  if [[ -r /dev/kvm ]] && [[ -w /dev/kvm ]]; then
    QEMU_ARGS="-enable-kvm -cpu host"
  else
    QEMU_ARGS="-cpu qemu64"
  fi
elif [[ "$ARCH" == "arm64" ]]; then
  QEMU_CMD="qemu-system-aarch64"
  QEMU_ARGS="-cpu cortex-a57 -machine virt"
else
  echo "❌ Unsupported architecture: $ARCH"
  exit 1
fi

# Check QEMU availability
if ! command -v "$QEMU_CMD" &> /dev/null; then
  echo "❌ $QEMU_CMD not found. Please install QEMU for $ARCH architecture."
  exit 1
fi

# Start QEMU VM in background
echo "🖥️ Starting QEMU VM..."
echo "🔧 Command: $QEMU_CMD $QEMU_ARGS -m $VM_RAM ..."
$QEMU_CMD \
  $QEMU_ARGS \
  -m "$VM_RAM" \
  -drive file="$WORK_IMG",format=raw,if=virtio \
  -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22,hostfwd=tcp::${HTTP_PORT}-:8581 \
  -device virtio-net,netdev=net0 \
  -nographic \
  -serial mon:stdio \
  -daemonize \
  -pidfile vm.pid

VM_PID=$(cat vm.pid)
echo "🔧 VM started with PID: $VM_PID"

# Cleanup function
cleanup() {
  echo "🧹 Cleaning up..."
  if [[ -n "${VM_PID:-}" ]] && kill -0 "$VM_PID" 2>/dev/null; then
    echo "🛑 Stopping VM (PID: $VM_PID)..."
    kill "$VM_PID" 2>/dev/null || true
    sleep 2
    kill -9 "$VM_PID" 2>/dev/null || true
  fi
  rm -f vm.pid
  rm -f "$WORK_IMG"
}

trap cleanup EXIT

# Wait for VM to boot and services to start
echo "⏳ Waiting for VM to boot and services to start..."
boot_success=false
start_time=$(date +%s)

for ((i=1; i<=TIMEOUT; i+=5)); do
  current_time=$(date +%s)
  elapsed=$((current_time - start_time))
  
  if [[ $elapsed -gt $TIMEOUT ]]; then
    echo "❌ Timeout waiting for VM to boot (${TIMEOUT}s)"
    exit 1
  fi
  
  # Check if VM is still running
  if ! kill -0 "$VM_PID" 2>/dev/null; then
    echo "❌ VM process died unexpectedly"
    exit 1
  fi
  
  # Try to connect to HTTP port (Homebridge web interface)
  if curl -s --connect-timeout 2 --max-time 5 "http://localhost:${HTTP_PORT}" >/dev/null 2>&1; then
    boot_success=true
    echo "✅ VM booted successfully and Homebridge web interface is accessible!"
    break
  fi
  
  echo "⏳ Still waiting... (${elapsed}s/${TIMEOUT}s)"
  sleep 5
done

if [[ "$boot_success" != "true" ]]; then
  echo "❌ VM failed to boot properly or Homebridge web interface not accessible within ${TIMEOUT}s"
  exit 1
fi

# Additional validation: Check if we can get a response from Homebridge
echo "🔍 Validating Homebridge web interface..."
response=$(curl -s --connect-timeout 5 --max-time 10 "http://localhost:${HTTP_PORT}" || echo "")

if [[ -n "$response" ]]; then
  echo "✅ Homebridge web interface responded successfully!"
  
  # Check if response looks like Homebridge (should contain some typical content)
  if echo "$response" | grep -qi "homebridge\|login\|dashboard" 2>/dev/null; then
    echo "✅ Response appears to be from Homebridge application"
  else
    echo "⚠️ Warning: Response doesn't appear to be from Homebridge, but service is running"
  fi
else
  echo "❌ No response from Homebridge web interface"
  exit 1
fi

echo "🎉 VM image validation completed successfully for $ARCH!"
echo "✅ VM boots properly"
echo "✅ Homebridge service starts"
echo "✅ Web interface accessible on port $HTTP_PORT"

exit 0
#!/usr/bin/env bash

BASH_DEBUG="" # "" or "x" for debugging

set -euo${BASH_DEBUG} pipefail

# VirtualBox OVA Validation Script
# Validates that the OVA file boots and serves the Homebridge web interface.

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging functions
log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARN:${NC} $*" >&2; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $*" >&2; }
info() { echo -e "${BLUE}[$(date +'%H:%M:%S')] INFO:${NC} $*" >&2; }
group_log() {
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        echo -e "::group::$*"
    else
        log "$*"
    fi
}
group_end() { echo -e "::endgroup::"; }

OVA_FILE="${1:-}"
VM_NAME="homebridge-validation-vm"
VM_RAM="1024"

TEST_URL="http://localhost:8581"

check_dependencies() {
  log "🔍 Checking dependencies..."
  if ! command -v VBoxManage &> /dev/null; then
    error "VirtualBox is required but not installed"
    echo "Please install VirtualBox: https://www.virtualbox.org/wiki/Downloads"
    exit 1
  fi
  if ! command -v curl &> /dev/null; then
    error "curl is required but not installed"
    echo "Please install curl: https://curl.se/"
    exit 1
  fi
}

import_ova() {
  if [[ ! -f "$OVA_FILE" ]]; then
    error "OVA file not found: $OVA_FILE"
    exit 1
  fi

  group_log "📦 Importing OVA file into VirtualBox..."
  VBoxManage import "$OVA_FILE" --vsys 0 --vmname "$VM_NAME"
  VBoxManage modifyvm "${VM_NAME}" --nic1 nat
  VBoxManage modifyvm "${VM_NAME}" --natpf1 "www,tcp,,80,,80"
  VBoxManage modifyvm "${VM_NAME}" --natpf1 "hbui,tcp,,8581,,8581"
  VBoxManage modifyvm "${VM_NAME}" --natpf1 "homekit,tcp,,51826,,51826"
  group_end
  log "✅ OVA imported successfully: ${VM_NAME}"
}

start_vm() {
  log "🚀 Starting VM..."
  VBoxManage startvm "$VM_NAME" --type headless
  log "✅ VM started: $VM_NAME"
}

wait_for_homebridge() {
  log "⏳ Waiting for ${TEST_URL} to become available..."
  for i in {1..12}; do
    sleep 5
    STATUS=$(curl --max-time 5 -s -o /dev/null -w "%{http_code}" ${TEST_URL}|| echo "000")
    echo "HTTP status from Homebridge UI: $STATUS"
    if [[ "$STATUS" == "200" ]]; then
      echo "::notice::Homebridge UI responded with HTTP 200"
      break
    else
      echo "Waiting for Homebridge UI to respond... Current HTTP status: $STATUS"
    fi
  done
  if [[ "$STATUS" != "200" ]]; then
    echo "::error::Homebridge UI did not respond with HTTP 200"
    exit 1
  fi
}

check_json_field() {
  local json="$1"
  local field="$2"
  local expected_value="$3"

  # Extract the field's value using jq
  local actual_value
  actual_value=$(echo "$json" | jq -r "$field")

  # Compare the actual value with the expected value
  if [[ "$actual_value" != "$expected_value" ]]; then
    error "Expected $field to be '$expected_value', but got '$actual_value'"
    exit 1
  fi

  log "✅ $field matches the expected value: $expected_value"
}

check_homebridge_web_interface() {
  log "🌐 Checking Homebridge web interface..."

  local url="${TEST_URL}/api/auth/settings"
  log "🌐 Fetching JSON from $url..."
  local response
  response=$(curl --max-time 5 -s "$url")

  if [[ -z "$response" ]]; then
    error "No response received from $url"
    exit 1
  fi

  log "🔍 Validating specific fields in the JSON response..."

  # Validate specific fields
  check_json_field "$response" ".env.platform" "linux"
  check_json_field "$response" ".env.packageName" "homebridge-config-ui-x"
  check_json_field "$response" ".env.port" "8581"

  log "✅ JSON response contains the expected values."
}

cleanup_vm() {
  group_log "🧹 Cleaning up VM..."
  VBoxManage controlvm "$VM_NAME" poweroff || true
  VBoxManage unregistervm "$VM_NAME" --delete || true
  log "✅ VM removed: $VM_NAME"
  group_end
}

main() {
  echo "🔍 Validating Homebridge OVA"
  echo "============================="
  log "OVA File: $OVA_FILE"
  log "VM Name: $VM_NAME"

  check_dependencies
  import_ova
  start_vm
  wait_for_homebridge
  check_homebridge_web_interface
  cleanup_vm

  log "🎉 Validation completed successfully!"
}

main "$@"
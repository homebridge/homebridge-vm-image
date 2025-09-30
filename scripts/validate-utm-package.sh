#!/usr/bin/env bash

set -euo pipefail

# Homebridge UTM Package Validation Script

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARN:${NC} $*" >&2; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $*" >&2; }
info() { echo -e "${BLUE}[$(date +'%H:%M:%S')] INFO:${NC} $*" >&2; }
group_log() {
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        echo -e "::group::$*"
    else
        log "===> $* <==="
    fi
}
group_end() {
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        echo -e "::endgroup::"
    fi
}

UTM_BUNDLE="${1:-}"
VM_NAME="homebridge-validation-utm"
TEST_URL="http://localhost:8581"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATION_DIR="${REPO_ROOT}/validation"
mkdir -p "$VALIDATION_DIR"

check_dependencies() {
  group_log "🔍 Checking dependencies..."
  if ! command -v open &> /dev/null; then
    error "'open' command is required (macOS only)."
    exit 1
  fi
  if ! command -v curl &> /dev/null; then
    error "curl is required but not installed"
    exit 1
  fi
  if ! command -v jq &> /dev/null; then
    error "jq is required for JSON validation"
    exit 1
  fi
  if ! command -v tar &> /dev/null; then
    error "tar is required to extract .tgz files"
    exit 1
  fi
}

prepare_validation_bundle() {
  group_log "📦 Preparing validation bundle..."
  rm -rf "$VALIDATION_DIR"/*
  if [[ -f "$UTM_BUNDLE" && "$UTM_BUNDLE" == *.tgz ]]; then
    log "Expanding UTM bundle archive: $UTM_BUNDLE"
    tar -xzf "$UTM_BUNDLE" -C "$VALIDATION_DIR"
    # Find the .utm directory inside validation
    local utm_dir
    utm_dir=$(find "$VALIDATION_DIR" -type d -name "*.utm" | head -n 1)
    if [[ -z "$utm_dir" ]]; then
      error "No .utm directory found after extracting $UTM_BUNDLE"
      exit 1
    fi
    VALIDATE_BUNDLE="$utm_dir"
  elif [[ -d "$UTM_BUNDLE" ]]; then
    log "Copying UTM bundle directory: $UTM_BUNDLE"
    cp -R "$UTM_BUNDLE" "$VALIDATION_DIR/"
    # Find the .utm directory inside validation
    local utm_dir
    utm_dir=$(find "$VALIDATION_DIR" -type d -name "*.utm" | head -n 1)
    if [[ -z "$utm_dir" ]]; then
      error "No .utm directory found after copying $UTM_BUNDLE"
      exit 1
    fi
    VALIDATE_BUNDLE="$utm_dir"
  else
    error "UTM bundle not found or invalid: $UTM_BUNDLE"
    exit 1
  fi
  log "Validation bundle ready: $VALIDATE_BUNDLE"
}

configure_networking_shared() {
  group_log "🔧 Configuring networking to 'Shared Network'..."
  PLIST="$VALIDATE_BUNDLE/config.plist"
  if [[ ! -f "$PLIST" ]]; then
    error "config.plist not found in UTM bundle: $PLIST"
    exit 1
  fi
  if command -v /usr/libexec/PlistBuddy &> /dev/null; then
    /usr/libexec/PlistBuddy -c "Set :Networking:0:Mode shared" "$PLIST"
    log "✅ Networking set to 'Shared Network' in config.plist"
  else
    error "PlistBuddy not found. Cannot modify config.plist networking mode."
    exit 1
  fi
}

configure_vm_name() {
  group_log "🔧 Setting VM name in config.plist to '$VM_NAME'..."
  PLIST="$VALIDATE_BUNDLE/config.plist"
  if [[ ! -f "$PLIST" ]]; then
    error "config.plist not found in UTM bundle: $PLIST"
    exit 1
  fi
  if command -v /usr/libexec/PlistBuddy &> /dev/null; then
    # Set the VM name under Information:Name
    /usr/libexec/PlistBuddy -c "Set :Information:Name $VM_NAME" "$PLIST"
    log "✅ VM name set to '$VM_NAME' in config.plist (Information:Name)"
  else
    error "PlistBuddy not found. Cannot modify config.plist VM name."
    exit 1
  fi
}

start_vm() {
  group_log "🚀 Starting UTM VM..."
  open "$VALIDATE_BUNDLE"
  log "Waiting for VM to appear in UTM (utmctl list)..."
  # Wait for VM to be listed by utmctl (max 60s)
  for i in {1..12}; do
    sleep 5
    if utmctl list | grep -q "$VM_NAME"; then
      log "VM '$VM_NAME' is listed in UTM."
      break
    else
      log "Waiting for VM '$VM_NAME' to be listed... ($i/12)"
    fi
  done
  if ! utmctl list | grep -q "$VM_NAME"; then
    error "VM '$VM_NAME' did not appear in utmctl list after 60 seconds."
    exit 1
  fi

  log "Waiting for VM to start (state: running)..."
  for i in {1..12}; do
    sleep 5
    VM_STATE=$(utmctl list | grep "$VM_NAME" | awk '{print $3}')
    if [[ "$VM_STATE" == "running" ]]; then
      log "VM '$VM_NAME' is running."
      break
    else
      log "Waiting for VM to start... Current state: $VM_STATE ($i/12)"
    fi
  done
  if [[ "$VM_STATE" != "running" ]]; then
    error "VM '$VM_NAME' did not reach 'running' state after 60 seconds."
    exit 1
  fi

  log "Collecting VM IP address with utmctl ip-address..."
  VM_IP=$(utmctl ip-address "$VM_NAME" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
  if [[ -n "$VM_IP" ]]; then
    log "VM IP address: $VM_IP"
    TEST_URL="http://${VM_IP}:8581"
    export TEST_URL
  else
    warn "Could not determine VM IP address. TEST_URL remains as $TEST_URL"
  fi
}

wait_for_homebridge() {
  group_log "⏳ Waiting for ${TEST_URL} to become available..."
  for i in {1..24}; do
    sleep 5
    STATUS=$(curl --max-time 5 -s -o /dev/null -w "%{http_code}" "${TEST_URL}" || echo "000")
    log "HTTP status from Homebridge UI: $STATUS"
    if [[ "$STATUS" == "200" ]]; then
      log "Homebridge UI responded with HTTP 200"
      return 0
    else
      log "Waiting for Homebridge UI to respond... Current HTTP status: $STATUS"
    fi
  done
  error "Homebridge UI did not respond with HTTP 200"
  return 1
}

check_json_field() {
  local json="$1"
  local field="$2"
  local expected_value="$3"
  local actual_value
  actual_value=$(echo "$json" | jq -r "$field")
  if [[ "$actual_value" != "$expected_value" ]]; then
    error "Expected $field to be '$expected_value', but got '$actual_value'"
    exit 1
  fi
  log "✅ $field matches the expected value: $expected_value"
}

check_homebridge_web_interface() {
  group_log "🌐 Checking Homebridge web interface..."
  local url="${TEST_URL}/api/auth/settings"
  log "🌐 Fetching JSON from $url..."
  local response
  response=$(curl --max-time 5 -s "$url")
  if [[ -z "$response" ]]; then
    error "No response received from $url"
    exit 1
  fi
  log "🔍 Validating specific fields in the JSON response..."
  check_json_field "$response" ".env.platform" "linux"
  check_json_field "$response" ".env.packageName" "homebridge-config-ui-x"
  check_json_field "$response" ".env.port" "8581"
  log "✅ JSON response contains the expected values."
}

main() {
  log "🔍 Validating Homebridge UTM VM"
  log "=============================="
  info "UTM Bundle: $UTM_BUNDLE"
  info "VM Name: $VM_NAME"
  info "Test URL: $TEST_URL"
  info "REPO Root: $REPO_ROOT"
  info "Validation Directory: $VALIDATION_DIR"

  check_dependencies
  prepare_validation_bundle
  configure_vm_name
  # configure_networking_shared
  start_vm
  wait_for_homebridge
  check_homebridge_web_interface

  log "🎉 Validation completed successfully!"
  log "Please manually shut down the VM in UTM when finished."
}

main "$@"
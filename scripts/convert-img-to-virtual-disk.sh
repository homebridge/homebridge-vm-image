#! /bin/bash

set -e

VDISK_SIZE=50G  # Size of the virtual disk for each VM
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GITHUB_TAG="${1:-latest}"  # Github Release TAG, not required for local runs

if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  log "Using GitHub TAG: $GITHUB_TAG"
fi

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
        log "---> $* <---"
    fi
}
group_end() {
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        echo -e "::endgroup::"
    fi
}


for img in ${REPO_ROOT}/output/*.img; do
  log "Processing $img"
  group_log "Converting $img to qcow2"
  base_name=$(basename "$img" .img)
  # Convert to qcow2 format
  ext=qcow2
  out_file="${REPO_ROOT}/output/${base_name}.${ext}"
  qemu-img convert -c -O $ext "$img" "$out_file"
  log "Resizing $out_file to ${VDISK_SIZE}"
  qemu-img resize "$out_file" ${VDISK_SIZE}
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    log "Uploading $out_file to release"
    gh release upload "${GITHUB_TAG}" "$out_file" --clobber
    log "Deleting $out_file to save space"
    rm -f "$out_file"
  fi
  group_end
  # Remaining files don't have the -c option for qemu-img
  for ext in vhdx vmdk; do
    group_log "Converting $img to $ext"
    out_file="${REPO_ROOT}/output/${base_name}.${ext}"
    gz_file="${out_file}.gz"
    log "Converting $img to $ext format"
    qemu-img convert -O $ext "$img" "$out_file"
    # qemu-img resize "$out_file" ${VDISK_SIZE} || true   # only supported on qcow2 files
    log "Compressing $out_file"
    gzip -f -k "$out_file"
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
      log "Uploading $gz_file to release"
      gh release upload "${GITHUB_TAG}" "$gz_file" --clobber
      log "Deleting $out_file and $gz_file to save space"
      rm -f "$out_file" "$gz_file"
    fi
    group_end
  done
done
log "Deleting original IMG files"
rm -f ${REPO_ROOT}/output/*.img
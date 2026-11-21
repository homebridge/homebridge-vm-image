#! /bin/bash

set -e

# Size of the virtual disk of every format. The files stay small: only used blocks are stored.
# The system grows into the disk on its first start.
VDISK_SIZE="${VDISK_SIZE:-50G}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GITHUB_TAG="${1:-latest}"  # Github Release TAG, not required for local runs

# shellcheck source=lib.sh
source "${REPO_ROOT}/scripts/lib.sh"

if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  log "Using GitHub TAG: $GITHUB_TAG"
fi

for img in "${REPO_ROOT}"/output/*.img; do
  log "Processing $img"
  group_log "Converting $img to qcow2"
  base_name=$(basename "$img" .img)
  # Convert to qcow2 format
  ext=qcow2
  out_file="${REPO_ROOT}/output/${base_name}.${ext}"
  qemu-img convert -c -O "$ext" "$img" "$out_file"
  log "Resizing $out_file to ${VDISK_SIZE}"
  qemu-img resize "$out_file" "${VDISK_SIZE}"
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    log "Uploading $out_file to release"
    gh release upload "${GITHUB_TAG}" "$out_file" --clobber
    log "Deleting $out_file to save space"
    rm -f "$out_file"
  fi
  group_end
  # VHDX and VMDK get the same disk size as QCOW2. qemu-img can not resize a VMDK file, so both
  # are converted from a copy of the image that was grown first. The copy is sparse: the extra
  # space takes no room on the build machine.
  grown_img="${REPO_ROOT}/output/${base_name}.grown.raw"
  cp --sparse=always "$img" "$grown_img"
  qemu-img resize -q -f raw "$grown_img" "${VDISK_SIZE}"
  # Remaining files don't have the -c option for qemu-img
  for ext in vhdx vmdk; do
    group_log "Converting $img to $ext"
    out_file="${REPO_ROOT}/output/${base_name}.${ext}"
    gz_file="${out_file}.gz"
    log "Converting $img to $ext format (${VDISK_SIZE})"
    qemu-img convert -f raw -O "$ext" "$grown_img" "$out_file"
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
  rm -f "$grown_img"
done
log "Deleting original IMG files"
rm -f "${REPO_ROOT}"/output/*.img

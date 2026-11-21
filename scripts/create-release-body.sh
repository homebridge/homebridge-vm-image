#! /bin/bash

# Writes the release notes to output/release-body.md.
#
# Usage: create-release-body.sh <stable|beta|alpha>
#
# Environment:
#   CURRENT_TAG  the tag of the release being made (optional). When a second build on the same
#                day updates an existing release, that tag exists already. It is then left out
#                when the previous release is looked for, so the release is not compared with
#                itself.
#   GH_TOKEN     for "gh release download" (read access is enough).
#
# If used in GitHub Actions, ensure we have a full git history
#     - name: Checkout
#      uses: actions/checkout@v4
#      with:
#        fetch-depth: 0

# Exit on error
set -e

# Logging functions
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARN:${NC} $*" >&2; }
info() { echo -e "${BLUE}[$(date +'%H:%M:%S')] INFO:${NC} $*" >&2; }

# Determine repository root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PKG_RELEASE_STREAM="${1:-beta}"
CURRENT_TAG="${CURRENT_TAG:-}"

# The form of the release tags of each stream, and the folders of the OTHER streams.
case "$PKG_RELEASE_STREAM" in
  stable)
    TAG_FORM='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    OTHER_STREAMS=(beta alpha)
    ;;
  beta)
    TAG_FORM='^beta-[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    OTHER_STREAMS=(stable alpha)
    ;;
  alpha)
    TAG_FORM='^alpha-[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    OTHER_STREAMS=(stable beta)
    ;;
  *)
    echo "create-release-body.sh: the stream must be stable, beta or alpha" >&2
    exit 1
    ;;
esac

PREVIOUS_DIR="${REPO_ROOT}/.previous"
rm -rf "$PREVIOUS_DIR"
mkdir -p "$PREVIOUS_DIR"

OUTPUT_DIR="${REPO_ROOT}/output"
mkdir -p "$OUTPUT_DIR"

MANIFEST="${OUTPUT_DIR}/release-body.md"

info "Creating release body at ${MANIFEST}"

log "Adding header to release body"
cp "${REPO_ROOT}/assets/release-body-header.md" "$MANIFEST"
echo >> "$MANIFEST"

log "Adding package manifest section for stream: ${PKG_RELEASE_STREAM}"

# Add current manifest section
echo -e "\n## Current Package Manifests:\n" >> "$MANIFEST"

shopt -s nullglob
OUTPUT_MANIFESTS=("${OUTPUT_DIR}"/*.manifest)
shopt -u nullglob

for OUTPUT_MANIFEST in "${OUTPUT_MANIFESTS[@]}"; do
  # Extract the base name of the manifest file
  MANIFEST_NAME=$(basename "$OUTPUT_MANIFEST")

  # Create this line based on the manifest name - ### AMD64 Manifest
  if [[ "$MANIFEST_NAME" == *"amd64.manifest" ]]; then
    MANIFEST_HEADER="AMD64 Manifest"
  elif [[ "$MANIFEST_NAME" == *"arm64.manifest" ]]; then
    MANIFEST_HEADER="ARM64 Manifest"
  else
    MANIFEST_HEADER="$MANIFEST_NAME"
  fi

  log "Including manifest: $MANIFEST_NAME"
  {
    echo "### ${MANIFEST_HEADER}"
    echo
    cat "$OUTPUT_MANIFEST"
    echo
  } >> "$MANIFEST"
done

# The previous release of this stream: its newest tag (the tags sort by date), without the tag
# of the release that is being made now.
LATEST_TAG=$(git tag -l | grep -E "$TAG_FORM" | grep -vxF -- "${CURRENT_TAG:-no-current-tag}" | sort | tail -n 1 || true)

log "Previous release of stream '${PKG_RELEASE_STREAM}': ${LATEST_TAG:-none}"

# Check for package version changes if we have a previous tag
HAS_PACKAGE_CHANGES=false
PACKAGE_JSON_PATH="${PKG_RELEASE_STREAM}/package.json"
if [ -n "$LATEST_TAG" ]; then
  # Compare package versions with previous tag
  if git show "$LATEST_TAG:$PACKAGE_JSON_PATH" >/dev/null 2>&1; then
    # Define the list of dependencies to check
    DEPENDENCIES=(
      "@homebridge/homebridge-apt-pkg"
      "ffmpeg-for-homebridge"
    )

    # Iterate through the dependencies
    for DEP in "${DEPENDENCIES[@]}"; do
      # Get the previous version of the dependency from the latest tag
      PREV_VERSION=$(git show "$LATEST_TAG:$PACKAGE_JSON_PATH" 2>/dev/null | jq -r --arg dep "$DEP" '.dependencies[$dep] // "unknown"')

      # Get the current version of the dependency from the current package.json
      CURR_VERSION=$(jq -r --arg dep "$DEP" '.dependencies[$dep] // "unknown"' "${REPO_ROOT}/${PACKAGE_JSON_PATH}")

      # Check if the version has changed and add it to the changelog
      if [[ "$PREV_VERSION" != "$CURR_VERSION" && "$CURR_VERSION" != "unknown" ]]; then
        log "Dependency ${DEP} changed from ${PREV_VERSION} to ${CURR_VERSION}"
        if [ "$HAS_PACKAGE_CHANGES" = false ]; then
          log "Adding Package Version Changes section to release body"
          echo -e "## Package Version Changes" >> "$MANIFEST"
          echo >> "$MANIFEST"
          HAS_PACKAGE_CHANGES=true
        fi
        echo "* **${DEP}**: Updated from $PREV_VERSION to $CURR_VERSION" >> "$MANIFEST"
      fi
    done
  else
    warn "Could not find previous package.json at tag ${LATEST_TAG} for comparison."
  fi
fi

# The longest list of changed manifest lines that is shown for one file
MAX_DIFF_LINES=20

# With no previous release there is nothing to download. (An empty tag name would make gh take
# the newest release of ANY stream.)
if [ -n "$LATEST_TAG" ] && gh release download "$LATEST_TAG" --pattern "*.manifest" --dir "${PREVIOUS_DIR}" 2>/dev/null; then
  echo -e "\n## Changes Since Previous Release ($LATEST_TAG):\n" >> "$MANIFEST"

  # Iterate through all manifest files in ${OUTPUT_DIR}
  for OUTPUT_MANIFEST in "${OUTPUT_MANIFESTS[@]}"; do
    # Extract the base name of the manifest file
    MANIFEST_NAME=$(basename "$OUTPUT_MANIFEST")
    log "Processing manifest for changes: $MANIFEST_NAME"
    # Check if a corresponding file exists in ${PREVIOUS_DIR}
    PREVIOUS_MANIFEST="${PREVIOUS_DIR}/${MANIFEST_NAME}"
    if [[ -f "$PREVIOUS_MANIFEST" ]]; then
      TMP_DIFF="$(mktemp)"
      # Compare the manifests and capture differences
      if ! diff -u "$PREVIOUS_MANIFEST" "$OUTPUT_MANIFEST" > "${TMP_DIFF}" 2>/dev/null; then
        # The changed table lines, in the order of the manifest: an old line is followed by its new one
        CHANGED_LINES=$(grep -E "^[+-]\|" "${TMP_DIFF}" || true)
        if [ -n "$CHANGED_LINES" ]; then
          CHANGED_COUNT=$(printf '%s\n' "$CHANGED_LINES" | wc -l | tr -d ' ')
          {
            echo "### Changes in ${MANIFEST_NAME}"
            echo "\`\`\`diff"
            printf '%s\n' "$CHANGED_LINES" | head -n "$MAX_DIFF_LINES"
            echo "\`\`\`"
            if [ "$CHANGED_COUNT" -gt "$MAX_DIFF_LINES" ]; then
              echo "_The list is cut: $((CHANGED_COUNT - MAX_DIFF_LINES)) more changed lines are not shown._"
            fi
          } >> "$MANIFEST"
        else
          echo "No meaningful changes detected in ${MANIFEST_NAME}." >> "$MANIFEST"
        fi
      else
        echo "No changes detected in ${MANIFEST_NAME}." >> "$MANIFEST"
      fi
      rm -f "${TMP_DIFF}"
    else
      # If no corresponding file exists in ${PREVIOUS_DIR}, note it in the manifest
      echo "No previous manifest found for ${MANIFEST_NAME}." >> "$MANIFEST"
    fi
  done
else
  echo -e "\n## Changes Since Previous Release\n" >> "$MANIFEST"
  echo "Previous release manifest not available for comparison." >> "$MANIFEST"
fi

# Commits for this stream: everything except the version files of the OTHER streams. The
# dependency bot commits those every day, and they change nothing in this stream's image.
COMMIT_PATHS=(.)
for OTHER in "${OTHER_STREAMS[@]}"; do
  COMMIT_PATHS+=(":(exclude)${OTHER}")
done

# add_commits <git log arguments...>: adds the commits as list entries; returns 1 when there are none
add_commits() {
  local commits commit
  commits=$(git log --oneline --no-merges "$@" -- "${COMMIT_PATHS[@]}" 2>/dev/null || true)
  [ -n "$commits" ] || return 1
  while IFS= read -r commit; do
    # Extract commit hash and message
    echo "* ${commit#* } (\`${commit%% *}\`)" >> "$MANIFEST"
  done <<< "$commits"
}

echo -e "\n### Homebridge VM Image Changes" >> "$MANIFEST"
if [ -n "$LATEST_TAG" ]; then
  # Commits since the previous release of this stream
  if [ "$HAS_PACKAGE_CHANGES" = true ]; then
    echo "### Code Changes" >> "$MANIFEST"
    echo >> "$MANIFEST"
  fi
  if ! add_commits "$LATEST_TAG"..HEAD; then
    echo "* No new commits since last ${PKG_RELEASE_STREAM} release" >> "$MANIFEST"
  fi
else
  # If no tags of this type exist, show recent commits
  echo "### Recent Changes" >> "$MANIFEST"
  echo >> "$MANIFEST"
  if ! add_commits -5; then
    echo "* No commit history available" >> "$MANIFEST"
  fi
fi

echo >> "$MANIFEST"

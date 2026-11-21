#!/usr/bin/env bash
# Helpers shared by the build, packaging and release scripts of this repo.
# Load it with:  source "<repo>/scripts/lib.sh"
#
# The scripts that run INSIDE the VM (assets/*/files) do not use this file: they are copied
# into the image one by one and must stand alone.

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions. They write to the error output, so the normal output of a script stays
# free for its result.
log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARN:${NC} $*" >&2; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $*" >&2; }
info() { echo -e "${BLUE}[$(date +'%H:%M:%S')] INFO:${NC} $*" >&2; }

# group_log <title> ... group_end: a folded section in the log of a GitHub workflow run
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

# Prints the CPU type of this machine in Debian's words: arm64 or amd64.
detect_arch() {
    case "$(uname -m)" in
        arm64 | aarch64) echo "arm64" ;;
        *) echo "amd64" ;;
    esac
}

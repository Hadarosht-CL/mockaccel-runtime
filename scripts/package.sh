#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# scripts/package.sh
#
# Produces distributable artifacts from a successful build:
#   - Docker image of the daemon          (Stage 7)
#   - Python wheel for pymockaccel        (Stage 7)
#   - C++ ARM64 tarball for the daemon    (Stage 7)
#
# Today this is a stub: the verb is locked in so Stage 6 (CI) can call
# it as a one-liner, and Stage 7 lands as a focused MR (Merge Request)
# that only replaces the body of main().
#
# Exit codes:
#   0   success
#   1   generic failure
#   2   usage error
#   64  docker build failed
#   65  missing cross artifact (Step 3)
#   67  not yet implemented (aarch64 in Step 2)

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# --- usage -----------------------------------------------------------------
usage() {
    cat <<'EOF'
Usage: package.sh [--help]

Produces distributable artifacts. Not implemented yet; lands in Stage 7.

Options:
  --target=T      Build target. T is one of:
                    host     build for the current host (default).
                    aarch64  cross-compile for 64-bit ARM Linux using
                             cmake/toolchains/aarch64-linux-gnu.cmake.
                             Requires aarch64-linux-gnu-g++ on PATH.
  --clean         Remove the build directory before configuring.
  --debug         Configure as Debug. Default: Release.
  --jobs N        Parallel build jobs. Default: cmake's auto-detect.
  --build-dir DIR Build directory. Default: 'build' for host,
                  'build-aarch64' for aarch64, or $BUILD_DIR.
  -h, --help      Show this help and exit.

Environment:
  (future update in step 4)

Options:
  -h, --help    Show this help and exit.

Exit codes:
  0   package success
  1   generic failure
  2   usage error
  64  docker build failed
  65  missing cross artifact (future, step 3)
  67  not yet implemented (aarch64 in Step 2)
EOF
}

# CI plumbing
target="host"

# --- arg parsing -----------------------------------------------------------
while (($# > 0)); do
    case "$1" in
        --target)
            shift
            if (($# == 0)); then
                log_error "--target requires a value"
                usage >&2
                exit 2
            fi
            target="$1"
            ;;
        --target=*) target="${1#*=}" ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            log_error "unknown argument: $1"
            usage >&2
            exit 2
            ;;
    esac
    shift
done

# Validate --target
case "${target}" in
    host | aarch64) ;;
    *) die "--target must be 'host' or 'aarch64', got '${target}'" 2 ;;
esac

# --- main ------------------------------------------------------------------
main() {
    local arch_label
    require_cmd docker
    case "${target}" in
        host) arch_label="amd64" ;;
        aarch64) arch_label="arm64" ;;
    esac

    local short_sha
    short_sha="$(git -C "$(repo_root)" rev-parse --short HEAD 2>/dev/null || echo unknown)"

    local tag="mockaccel-runtime:dev-${arch_label}-${short_sha}"
    log_step "package: target=${target} tag=${tag}"

    case "${target}" in
        host)
            if ! docker build -t "${tag}" "$(repo_root)"; then
                die "package: docker build failed: 64"
            fi
            log_step "package: done"
            log_info "image: ${tag}"
            ;;
        aarch64)
            log_warn "package: --target=aarch64 is wired in step 3 of stage 7"
            log_info "tag would be: ${tag}"
            exit 67
            ;;
    esac
    exit 0
}

main "$@"

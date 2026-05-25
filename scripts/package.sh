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
#   0   nothing to do (stub) or all artifacts produced
#   1   generic failure
#   2   usage error
#   64  packaging step failed (reserved for Stage 7)

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

Planned artifacts:
  - docker image: mockaccel/device-simulator:<version>
  - python wheel: pymockaccel-<version>-*.whl
  - arm64 tarball: mockaccel-runtime-<version>-aarch64.tar.gz

Options:
  -h, --help    Show this help and exit.

Exit codes:
  0   stub success / future: all artifacts produced
  2   usage error
  64  packaging step failed (future)
EOF
}

# --- arg parsing -----------------------------------------------------------
while (($# > 0)); do
    case "$1" in
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
    # SC2317: every case currently exits, making `shift` unreachable.
    # Kept on purpose: Stage 7 will add real flags that fall through,
    # and the rest of scripts/ uses this exact loop shape.
    # shellcheck disable=SC2317
    shift
done

# --- main ------------------------------------------------------------------
main() {
    log_step "package: stub"
    log_warn "package.sh is not implemented yet (lands in Stage 7)"
    log_info "this stub locks the verb name so CI in Stage 6 can call ./scripts/package.sh"
    exit 0
}

main "$@"

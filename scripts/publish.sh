#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# scripts/publish.sh
#
# Pushes built artifacts to an artifact registry:
#   - Docker images to a docker-local-dev repo on every main commit.
#   - Python wheel + ARM tarball to generic repos.
#
# Today this is a stub: the verb is locked in so Stage 6 (CI) can call
# it as a one-liner, and Stage 7 lands as a focused MR (Merge Request)
# that only replaces the body of main().
#
# Exit codes:
#   0   stub success / future: artifacts published
#   1   generic failure
#   2   usage error
#   64  publish step failed (reserved for Stage 7)

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# --- usage -----------------------------------------------------------------
usage() {
    cat <<'EOF'
Usage: publish.sh [--help]

Pushes built artifacts to an artifact registry. Not implemented yet;
lands in Stage 7 (Docker + Artifactory).

Planned steps:
  1. Authenticate to JFrog Artifactory Cloud free tier.
  2. Push Docker image to docker-local-dev (or docker-local-prod on tag).
  3. Upload Python wheel to a generic repo.
  4. Upload C++ ARM tarball to a generic repo.

Options:
  -h, --help    Show this help and exit.

Exit codes:
  0   stub success / future: artifacts published
  2   usage error
  64  publish step failed (future)
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
    log_step "publish: stub"
    log_warn "publish.sh is not implemented yet (lands in Stage 7)"
    log_info "this stub locks the verb name so CI in Stage 6 can call ./scripts/publish.sh"
    exit 0
}

main "$@"

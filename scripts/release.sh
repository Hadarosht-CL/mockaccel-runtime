#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# scripts/release.sh
#
# Tag-driven release flow:
#   - Verifies the working tree is clean and on a release tag.
#   - Generates CHANGELOG from Conventional Commits.
#   - Promotes artifacts in Artifactory from dev to prod.
#   - Signs checksums and creates the GitLab Release.
#
# Today this is a stub: the verb is locked in so Stage 6 (CI) can call
# it as a one-liner, and Stage 10 lands as a focused MR (Merge Request)
# that only replaces the body of main().
#
# Exit codes:
#   0   stub success / future: release published
#   1   generic failure
#   2   usage error
#   64  release step failed (reserved for Stage 10)

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# --- usage -----------------------------------------------------------------
usage() {
    cat <<'EOF'
Usage: release.sh [--help]

Drives a tag-triggered release. Not implemented yet; lands in Stage 10.

Planned steps:
  1. Verify clean tree and that HEAD points at a v*.*.* tag.
  2. Generate CHANGELOG.md from Conventional Commits (git-cliff).
  3. Promote artifacts in Artifactory: docker-local-dev -> docker-local-prod.
  4. Sign checksums (sha256sum + gpg --detach-sign).
  5. Create the GitLab Release with notes pulled from CHANGELOG.

Options:
  -h, --help    Show this help and exit.

Exit codes:
  0   stub success / future: release published
  2   usage error
  64  release step failed (future)
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
    log_step "release: stub"
    log_warn "release.sh is not implemented yet (lands in Stage 10)"
    log_info "this stub locks the verb name so CI in Stage 6 can call ./scripts/release.sh"
    exit 0
}

main "$@"

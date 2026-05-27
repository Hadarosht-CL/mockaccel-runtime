#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# scripts/deploy.sh
#
# Deploys the SUT (System Under Test) to a target environment:
#   - helm upgrade --install of the mockaccel chart against a k3s cluster.
#
# Today this is a stub: the verb is locked in so Stage 6 (CI) can call
# it as a one-liner, and Stage 9 lands as a focused MR (Merge Request)
# that only replaces the body of main().
#
# Exit codes:
#   0   stub success / future: deploy succeeded
#   1   generic failure
#   2   usage error
#   64  deploy step failed (reserved for Stage 9)

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# --- usage -----------------------------------------------------------------
usage() {
    cat <<'EOF'
Usage: deploy.sh [--help]

Deploys the SUT to a Kubernetes target. Not implemented yet; lands in
Stage 9 (Kubernetes).

Planned steps:
  1. Verify kubectl and helm are available and pointing at a k3s context.
  2. helm lint charts/mockaccel.
  3. helm upgrade --install mockaccel charts/mockaccel.
  4. Wait for rollout and run a smoke test against the deployed pod.

Options:
  -h, --help    Show this help and exit.

Exit codes:
  0   stub success / future: deploy succeeded
  2   usage error
  64  deploy step failed (future)
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
    # Kept on purpose: Stage 9 will add real flags that fall through,
    # and the rest of scripts/ uses this exact loop shape.
    # shellcheck disable=SC2317
    shift
done

# --- main ------------------------------------------------------------------
main() {
    log_step "deploy: stub"
    log_warn "deploy.sh is not implemented yet (lands in Stage 9)"
    log_info "this stub locks the verb name so CI in Stage 6 can call ./scripts/deploy.sh"
    exit 0
}

main "$@"

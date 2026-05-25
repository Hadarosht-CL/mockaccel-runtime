#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# scripts/test.sh
#
# Runs every registered test suite for this repo. Today no suites are
# registered, so this script is intentionally a thin, exit-0 placeholder
# whose only job is to lock the verb name and the call contract for CI.
#
# Suites land in later stages:
#   - Stage 2: pytest    (Python unit tests + framework skeleton)
#   - Stage 5: ctest     (C++ unit/integration tests against the SUT)
#   - Stage 5: bats-core (tests of the Bash scripts themselves)
#
# When a suite lands, replace the matching TODO block below with the
# real invocation. Keep the contract: each suite is a function, main()
# calls them in order, the first failure exits non-zero, and the script
# is still callable as `./scripts/test.sh` with no flags.
#
# Exit codes:
#   0   all registered suites passed (or no suites registered yet)
#   1   generic failure
#   2   usage error
#   64  a registered suite failed (set by the failing suite)

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# --- usage -----------------------------------------------------------------
usage() {
    cat <<'EOF'
Usage: test.sh [--suite NAME] [--build-dir DIR] [--help]

Runs all registered test suites. With no flags, runs every suite.

Options:
  --suite NAME    Run only the named suite. Repeatable.
                  Valid names (when implemented): pytest, ctest, bats.
                  Today every name reports "not implemented yet".
  --build-dir DIR Build directory ctest will look in. Default: $BUILD_DIR
                  or 'build'.
  -h, --help      Show this help and exit.

Environment:
  BUILD_DIR       Overrides the default build directory ('build').

Exit codes:
  0   all selected suites passed (or none registered)
  2   usage error
  64  a suite failed
EOF
}

# --- arg parsing -----------------------------------------------------------
selected_suites=()
build_dir="${BUILD_DIR:-build}"

while (($# > 0)); do
    case "$1" in
        --suite)
            shift
            if (($# == 0)); then
                log_error "--suite requires a value"
                usage >&2
                exit 2
            fi
            selected_suites+=("$1")
            ;;
        --suite=*) selected_suites+=("${1#*=}") ;;
        --build-dir)
            shift
            if (($# == 0)); then
                log_error "--build-dir requires a value"
                usage >&2
                exit 2
            fi
            build_dir="$1"
            ;;
        --build-dir=*) build_dir="${1#*=}" ;;
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

# Validate suite names. The ${arr[@]+"${arr[@]}"} idiom expands to nothing
# when the array is empty, instead of erroring under `set -u` on bash 3.2
# (which ships on macOS).
for s in ${selected_suites[@]+"${selected_suites[@]}"}; do
    case "${s}" in
        pytest | ctest | bats) ;;
        *) die "unknown suite: '${s}' (valid: pytest, ctest, bats)" 2 ;;
    esac
done

# Default: every suite.
if ((${#selected_suites[@]} == 0)); then
    selected_suites=(pytest ctest bats)
fi

# --- suites ----------------------------------------------------------------
# Each suite is a single function. When you implement one:
#   1. Replace the body below the TODO marker with the real invocation.
#   2. On suite failure, the function should `return 64` so main()
#      surfaces a stable exit code to CI.
#   3. Keep the leading require_cmd / availability check so the script
#      gives a clear error if its tools are not installed.

# Stage 2 will replace this with:
#   require_cmd pytest
#   pytest tests/ || return 64
suite_pytest() {
    log_step "test: pytest"
    log_warn "pytest suite not implemented yet (lands in Stage 2)"
    return 0
}

# Stage 5 will replace this with:
#   require_cmd ctest
#   ctest --test-dir "${build_dir}" --output-on-failure || return 64
suite_ctest() {
    log_step "test: ctest"
    log_warn "ctest suite not implemented yet (lands in Stage 5)"
    log_info "would look in build_dir=${build_dir}"
    return 0
}

# Stage 5 will replace this with:
#   require_cmd bats
#   bats tests/bash/ || return 64
suite_bats() {
    log_step "test: bats"
    log_warn "bats suite not implemented yet (lands in Stage 5)"
    return 0
}

# --- main ------------------------------------------------------------------
main() {
    log_step "test: running ${#selected_suites[@]} suite(s): ${selected_suites[*]}"

    local s
    for s in "${selected_suites[@]}"; do
        case "${s}" in
            pytest) suite_pytest ;;
            ctest) suite_ctest ;;
            bats) suite_bats ;;
        esac
    done

    log_step "test: done"
    log_info "no registered suites failed (none are implemented yet)"
}

main "$@"

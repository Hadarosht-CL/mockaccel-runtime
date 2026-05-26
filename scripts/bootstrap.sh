#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# scripts/bootstrap.sh
#
# Install the host toolchain needed to build, test, and lint this repo on
# Ubuntu/Debian Linux. Idempotent: re-running is a no-op when everything
# is already present.
#
# Intended callers:
#   - A developer setting up a fresh Linux box or container.
#   - CI (Continuous Integration) runners at the start of a pipeline.
#
# macOS is not supported by this script; macOS developers install the
# same tools via Homebrew (instructions printed on macOS).
#
# Exit codes:
#   0   success (or no-op)
#   1   generic failure
#   2   usage error or unsupported platform
#   64  apt-get update / install failed

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# --- usage -----------------------------------------------------------------
usage() {
    cat <<'EOF'
Usage: bootstrap.sh [--yes] [--no-update] [--help]

Installs the host toolchain on Ubuntu/Debian:
  build-essential cmake ninja-build git
  python3 python3-venv python3-pip
  shellcheck shfmt

Options:
  --yes         Pass -y to apt-get (non-interactive). Default: on when
                running as root or under CI; off otherwise.
  --no-update   Skip 'apt-get update'. Useful when the caller already
                refreshed the package index in this session.
  -h, --help    Show this help and exit.

Environment:
  CI            If set (any non-empty value), --yes is assumed.

Exit codes:
  0  success / nothing to do
  2  usage error or unsupported platform
  64 apt-get failed
EOF
}

# --- arg parsing -----------------------------------------------------------
assume_yes=0
do_update=1

while (($# > 0)); do
    case "$1" in
        --yes) assume_yes=1 ;;
        --no-update) do_update=0 ;;
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

# --- platform detection ----------------------------------------------------
detect_platform() {
    case "$(uname -s)" in
        Linux) ;;
        Darwin)
            cat >&2 <<'EOF'
bootstrap.sh does not run on macOS. Install the toolchain manually:

  brew install cmake ninja shellcheck shfmt
  # python3 ships with macOS; python3-venv/pip are bundled.

CI runs this script on Ubuntu/Debian only; macOS support is local-only
and intentionally manual.
EOF
            exit 2
            ;;
        *)
            die "unsupported OS: $(uname -s)" 2
            ;;
    esac

    if [[ ! -r /etc/os-release ]]; then
        die "cannot read /etc/os-release; unsupported Linux distribution" 2
    fi
    # shellcheck disable=SC1091  # sourced for ID/ID_LIKE
    . /etc/os-release
    case "${ID:-}:${ID_LIKE:-}" in
        ubuntu:* | debian:* | *:*debian* | *:*ubuntu*) ;;
        *)
            die "unsupported distribution: ID=${ID:-?} ID_LIKE=${ID_LIKE:-?} (need Debian/Ubuntu)" 2
            ;;
    esac
}

# --- privilege helper ------------------------------------------------------
# Pick the command prefix that gives apt-get root. Empty if already root.
sudo_prefix() {
    if [[ "$(id -u)" -eq 0 ]]; then
        printf ''
        return 0
    fi
    if command -v sudo >/dev/null 2>&1; then
        printf 'sudo'
        return 0
    fi
    die "this script needs root to run apt-get; install sudo or run as root" 2
}

# --- main ------------------------------------------------------------------
main() {
    log_step "bootstrap: detecting platform"
    detect_platform

    # Auto-yes when running unattended (root or CI).
    if [[ "${assume_yes}" -eq 0 ]] && { [[ "$(id -u)" -eq 0 ]] || [[ -n "${CI:-}" ]]; }; then
        assume_yes=1
    fi

    local apt_yes=""
    if [[ "${assume_yes}" -eq 1 ]]; then
        apt_yes="-y"
    fi

    local sudo
    sudo="$(sudo_prefix)"

    # Packages we install. Order is alphabetical for review-ability.
    local -a packages=(
        build-essential
        cmake
        git
        ninja-build
        python3
        python3-dev
        python3-pip
        python3-venv
        shellcheck
        shfmt
    )

    if [[ "${do_update}" -eq 1 ]]; then
        log_step "bootstrap: apt-get update"
        # 'retry' is defined in common.sh. apt-get update is the classic
        # transient-failure command; retry is cheap insurance.
        # shellcheck disable=SC2086  # we want $sudo to word-split when empty
        if ! retry 3 2 -- $sudo apt-get update; then
            die "apt-get update failed" 64
        fi
    else
        log_info "bootstrap: skipping apt-get update (--no-update)"
    fi

    log_step "bootstrap: installing ${#packages[@]} packages"
    log_info "packages: ${packages[*]}"
    # shellcheck disable=SC2086
    if ! retry 3 2 -- $sudo apt-get install ${apt_yes} --no-install-recommends "${packages[@]}"; then
        die "apt-get install failed" 64
    fi

    log_step "bootstrap: verifying tools are on PATH"
    require_cmd \
        cc \
        cmake \
        git \
        ninja \
        python3 \
        pip3 \
        shellcheck \
        shfmt

    log_step "bootstrap: done"
    log_info "host toolchain ready"
}

main "$@"

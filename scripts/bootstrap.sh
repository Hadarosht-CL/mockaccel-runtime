#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# scripts/bootstrap.sh
#
# Install the host toolchain needed to build, test, and lint this repo on
# Ubuntu/Debian Linux, then create a project virtual environment at
# .venv/ with the Python dev deps declared in pyproject.toml's [dev]
# extras (pytest, pytest-cov, ruff, mypy). Idempotent: re-running is a
# no-op when everything is already present.
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
Usage: bootstrap.sh [--yes] [--no-update] [--no-venv] [--help]

Installs the host toolchain on Ubuntu/Debian:
  build-essential cmake ninja-build git
  python3 python3-venv python3-pip
  shellcheck shfmt

Then creates .venv/ at the repo root and installs the Python dev deps
declared in pyproject.toml's [dev] extras (pytest, pytest-cov, ruff,
mypy) via 'pip install -e ".[dev]"'.

Options:
  --yes         Pass -y to apt-get (non-interactive). Default: on when
                running as root or under CI; off otherwise.
  --no-update   Skip 'apt-get update'. Useful when the caller already
                refreshed the package index in this session.
  --no-venv     Skip the .venv/ creation and 'pip install -e ".[dev]"'.
                Useful for CI stages that only need the apt toolchain
                (e.g. the Stage 4 cross-compile container).
  -h, --help    Show this help and exit.
EOF
}

# --- arg parsing -----------------------------------------------------------
assume_yes=0
do_update=1
do_venv=1

while (($# > 0)); do
    case "$1" in
        --yes) assume_yes=1 ;;
        --no-update) do_update=0 ;;
        --no-venv) do_venv=0 ;;
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

Then create the project venv the same way bootstrap.sh would:

  python3 -m venv .venv
  .venv/bin/pip install --upgrade pip
  .venv/bin/pip install -e ".[dev]"

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

# --- venv setup ------------------------------------------------------------
# Create (if missing) and populate the project virtual environment at
# .venv/ in the repo root with the dev deps from pyproject.toml's [dev]
# extras. Idempotent: re-running on an already-populated venv just
# re-checks the install. Linux-only path; macOS users get the same
# commands printed by detect_platform.
setup_venv() {
    local repo
    repo="$(repo_root)"
    local venv_dir="${repo}/.venv"

    # Idempotency probe: the venv is "populated" when its pip exists.
    # Probing the directory alone is not enough; an empty directory can
    # exist for legitimate reasons (e.g. Docker anonymous-volume masking
    # creates /repo/.venv as an empty mount point before this runs).
    local pip="${venv_dir}/bin/pip"
    if [[ ! -x "${pip}" ]]; then
        log_step "bootstrap: creating venv at ${venv_dir}"
        if ! python3 -m venv "${venv_dir}"; then
            die "python3 -m venv failed" 64
        fi
        if [[ ! -x "${pip}" ]]; then
            die "venv pip not found at ${pip} after python3 -m venv" 64
        fi
    else
        log_info "bootstrap: venv already populated at ${venv_dir}"
    fi

    log_step "bootstrap: upgrading pip inside venv"
    if ! "${pip}" install --upgrade --disable-pip-version-check pip; then
        die "pip self-upgrade failed" 64
    fi

    log_step "bootstrap: installing dev deps via pip install -e \".[dev]\""
    if ! (cd "${repo}" && "${pip}" install --disable-pip-version-check -e ".[dev]"); then
        die "pip install -e \".[dev]\" failed" 64
    fi

    log_info "venv ready; activate with: source ${venv_dir}/bin/activate"
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

    if [[ "${do_venv}" -eq 1 ]]; then
        setup_venv
    else
        log_info "bootstrap: skipping venv setup (--no-venv)"
    fi

    log_step "bootstrap: done"
    log_info "host toolchain ready"
}

main "$@"

#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# scripts/build.sh
#
# Configure and build the SUT (System Under Test) via CMake + Ninja.
# This is the single entry point CI and developers use to build the repo.
#
# Today it builds for the host. In Stage 4, a `--target` flag will be
# added for cross-compilation to ARM64; the placeholder is documented
# in --help below so the contract is visible early.
#
# Exit codes:
#   0   build succeeded
#   1   generic failure
#   2   usage error
#   64  cmake configure failed
#   65  cmake build failed

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# --- usage -----------------------------------------------------------------
usage() {
    cat <<'EOF'
Usage: build.sh [--clean] [--debug] [--jobs N] [--build-dir DIR] [--help]

Configures the repo with CMake and builds it with Ninja.

Options:
  --clean         Remove the build directory before configuring.
  --debug         Configure as Debug. Default: Release.
  --jobs N        Parallel build jobs. Default: cmake's auto-detect.
  --build-dir DIR Build directory. Default: $BUILD_DIR or 'build'.
  -h, --help      Show this help and exit.

Environment:
  BUILD_DIR       Overrides the default build directory ('build').
  CMAKE_FLAGS     Extra flags appended to the cmake configure step.

Future (Stage 4):
  --target=host|aarch64   Selects the toolchain. Not implemented yet;
                          all builds today target the host.

Exit codes:
  0   build succeeded
  2   usage error
  64  cmake configure failed
  65  cmake build failed
EOF
}

# --- defaults --------------------------------------------------------------
clean=0
build_type="Release"
jobs=""
build_dir="${BUILD_DIR:-build}"

# --- arg parsing -----------------------------------------------------------
while (($# > 0)); do
    case "$1" in
        --clean) clean=1 ;;
        --debug) build_type="Debug" ;;
        --jobs)
            shift
            if (($# == 0)); then
                log_error "--jobs requires a value"
                usage >&2
                exit 2
            fi
            jobs="$1"
            ;;
        --jobs=*) jobs="${1#*=}" ;;
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
        --target | --target=*)
            log_error "--target is reserved for future project development"
            exit 2
            ;;
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

# Validate --jobs is a positive integer if provided.
if [[ -n "${jobs}" ]] && ! [[ "${jobs}" =~ ^[1-9][0-9]*$ ]]; then
    die "--jobs must be a positive integer, got '${jobs}'" 2
fi

# --- main ------------------------------------------------------------------
main() {
    require_cmd cmake ninja

    local root
    root="$(repo_root)"

    # Resolve build_dir to an absolute path anchored at the repo root if
    # the user gave a relative path. Keeps behavior identical regardless
    # of the caller's current working directory.
    if [[ "${build_dir}" != /* ]]; then
        build_dir="${root}/${build_dir}"
    fi

    log_step "build: target=host type=${build_type} dir=${build_dir}"

    if [[ "${clean}" -eq 1 ]]; then
        if [[ -e "${build_dir}" ]]; then
            log_info "build: removing existing build dir"
            rm -rf -- "${build_dir}"
        else
            log_info "build: --clean requested, but build dir does not exist"
        fi
    fi

    # CMAKE_FLAGS is intentionally word-split so callers can pass
    # multiple flags via the environment, e.g.
    #   CMAKE_FLAGS="-DMOCKACCEL_BUILD_PYTHON=OFF -DFOO=BAR" scripts/build.sh
    local -a extra_flags=()
    if [[ -n "${CMAKE_FLAGS:-}" ]]; then
        # shellcheck disable=SC2206  # deliberate word-split for env-supplied flags
        extra_flags=(${CMAKE_FLAGS})
    fi

    log_step "build: configuring"
    if ! cmake \
        -S "${root}" \
        -B "${build_dir}" \
        -G Ninja \
        -DCMAKE_BUILD_TYPE="${build_type}" \
        "${extra_flags[@]}"; then
        die "cmake configure failed" 64
    fi

    log_step "build: compiling"
    local -a build_cmd=(cmake --build "${build_dir}")
    if [[ -n "${jobs}" ]]; then
        build_cmd+=(--parallel "${jobs}")
    fi
    if ! "${build_cmd[@]}"; then
        die "cmake build failed" 65
    fi

    log_step "build: done"
    log_info "artifacts in ${build_dir}"
}

main "$@"

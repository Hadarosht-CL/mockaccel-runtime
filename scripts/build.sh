#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# scripts/build.sh
#
# Configure and build the SUT (System Under Test) via CMake + Ninja.
# This is the single entry point CI and developers use to build the repo.
#
# --target=host    builds for the current host (default).
# --target=aarch64 cross-compiles the C++ pieces for 64-bit ARM Linux
#                  using cmake/toolchains/aarch64-linux-gnu.cmake.
#                  Requires aarch64-linux-gnu-g++ on PATH. Python
#                  bindings are forced OFF for the cross build.
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
Usage: build.sh [--target=host|aarch64] [--clean] [--debug] [--jobs N]
                [--build-dir DIR] [--help]

Configures the repo with CMake and builds it with Ninja.

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
  BUILD_DIR       Overrides the default build directory ('build').
  CMAKE_FLAGS     Extra flags appended to the cmake configure step.

Exit codes:
  0   build succeeded (or aarch64 stub no-op)
  2   usage error
  64  cmake configure failed
  65  cmake build failed
EOF
}

# --- defaults --------------------------------------------------------------
# build_dir stays empty here so we can pick a target-aware default
# (build/ for host, build-aarch64/ for cross) AFTER arg parsing.
clean=0
build_type="Release"
jobs=""
build_dir=""
target="host"

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

# Validate --target.
case "${target}" in
    host | aarch64) ;;
    *) die "--target must be 'host' or 'aarch64', got '${target}'" 2 ;;
esac

# Validate --jobs is a positive integer if provided.
if [[ -n "${jobs}" ]] && ! [[ "${jobs}" =~ ^[1-9][0-9]*$ ]]; then
    die "--jobs must be a positive integer, got '${jobs}'" 2
fi

# Resolve the default build directory now that --target and
# --build-dir have both been parsed. Precedence:
#   1. --build-dir / --build-dir=DIR  (explicit, wins)
#   2. BUILD_DIR env var              (explicit caller intent)
#   3. target-aware default           (build-aarch64 for cross, build for host)
if [[ -z "${build_dir}" ]]; then
    if [[ -n "${BUILD_DIR:-}" ]]; then
        build_dir="${BUILD_DIR}"
    elif [[ "${target}" == "aarch64" ]]; then
        build_dir="build-aarch64"
    else
        build_dir="build"
    fi
fi

# --- main ------------------------------------------------------------------
main() {
    require_cmd cmake ninja
    if [[ "${target}" == "aarch64" ]]; then
        require_cmd aarch64-linux-gnu-g++
    fi

    local root
    root="$(repo_root)"

    # Resolve build_dir to an absolute path anchored at the repo root if
    # the user gave a relative path. Keeps behavior identical regardless
    # of the caller's current working directory.
    if [[ "${build_dir}" != /* ]]; then
        build_dir="${root}/${build_dir}"
    fi

    log_step "build: target=${target} type=${build_type} dir=${build_dir}"

    if [[ "${clean}" -eq 1 ]]; then
        if [[ -e "${build_dir}" ]]; then
            log_info "build: removing existing build dir"
            rm -rf -- "${build_dir}"
        else
            log_info "build: --clean requested, but build dir does not exist"
        fi
    fi

    # Assemble CMake -D flags. Order matters: target-specific flags go
    # first so a caller-supplied CMAKE_FLAGS can still override them
    # (cmake honors the last -D for a given variable).
    local -a extra_flags=()
    if [[ "${target}" == "aarch64" ]]; then
        local toolchain="${root}/cmake/toolchains/aarch64-linux-gnu.cmake"
        extra_flags+=("-DCMAKE_TOOLCHAIN_FILE=${toolchain}")
        extra_flags+=("-DMOCKACCEL_BUILD_PYTHON=OFF")
    fi
    # CMAKE_FLAGS is intentionally word-split so callers can pass
    # multiple flags via the environment, e.g.
    #   CMAKE_FLAGS="-DMOCKACCEL_BUILD_PYTHON=OFF -DFOO=BAR" scripts/build.sh
    if [[ -n "${CMAKE_FLAGS:-}" ]]; then
        # shellcheck disable=SC2206  # deliberate word-split for env-supplied flags
        extra_flags+=(${CMAKE_FLAGS})
    fi

    log_step "build: configuring"
    if ! cmake \
        -S "${root}" \
        -B "${build_dir}" \
        -G Ninja \
        -DCMAKE_BUILD_TYPE="${build_type}" \
        ${extra_flags[@]+"${extra_flags[@]}"}; then
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

#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# scripts/lib/common.sh
#
# Shared Bash helpers sourced by every script under scripts/.
# Not executable on its own: sourcing-only, guarded below.
#
# Provides:
#   log_info / log_warn / log_error / log_step   - leveled, color-aware logging
#   die <msg> [exit_code]                        - log_error + exit
#   require_cmd <cmd> [cmd...]                   - die if any command is missing
#   retry <attempts> <base_sleep_seconds> -- <cmd...>
#                                                - retry with exponential backoff
#   mktempdir_trap [prefix]                      - mktemp -d + EXIT-trap cleanup,
#                                                  prints the path to stdout
#   repo_root                                    - prints the repo root absolute path
#
# Conventions:
#   - Honors NO_COLOR (https://no-color.org) and falls back to plain text
#     when stdout is not a TTY (Teletypewriter, i.e. non-terminal output).
#   - All logs go to stderr so stdout stays usable for command output.
#   - No global side effects on source (no `set -e` here; the sourcing script
#     owns its own strict mode).

# --- sourcing guard --------------------------------------------------------
# Refuse to be executed directly. ${BASH_SOURCE[0]} is this file; $0 is the
# entry point. They match only when this file was invoked, not sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    printf 'common.sh is a library; source it, do not execute it.\n' >&2
    exit 2
fi

# Re-source idempotency: if another script already sourced us in this shell,
# do not redefine everything.
if [[ "${_MOCKACCEL_COMMON_SH_LOADED:-0}" == "1" ]]; then
    return 0
fi
_MOCKACCEL_COMMON_SH_LOADED=1

# --- color setup -----------------------------------------------------------
# Decide once, at source time, whether to emit ANSI color escapes.
if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 2 ]]; then
    _C_RESET=""
    _C_DIM=""
    _C_RED=""
    _C_YELLOW=""
    _C_GREEN=""
    _C_BLUE=""
    _C_BOLD=""
else
    _C_RESET=$'\033[0m'
    _C_DIM=$'\033[2m'
    _C_RED=$'\033[31m'
    _C_YELLOW=$'\033[33m'
    _C_GREEN=$'\033[32m'
    _C_BLUE=$'\033[34m'
    _C_BOLD=$'\033[1m'
fi

# --- logging ---------------------------------------------------------------
# All logs go to stderr (>&2). The format is intentionally minimal:
#   LEVEL message
# Timestamps are deliberately omitted; CI log viewers already add them.

_log() {
    # $1 = color, $2 = level label, rest = message
    local color="$1" level="$2"
    shift 2
    printf '%s%s%s %s\n' "${color}" "${level}" "${_C_RESET}" "$*" >&2
}

log_info() { _log "${_C_BLUE}" "INFO " "$*"; }
log_warn() { _log "${_C_YELLOW}" "WARN " "$*"; }
log_error() { _log "${_C_RED}" "ERROR" "$*"; }

# log_step is for top-level progress markers ("Step 1: bootstrap").
# Visually heavier than log_info so the eye finds them in long CI output.
log_step() {
    printf '\n%s==> %s%s\n' "${_C_BOLD}${_C_GREEN}" "$*" "${_C_RESET}" >&2
}

# --- die -------------------------------------------------------------------
# Log an error and exit. Exit code defaults to 1.
die() {
    local msg="$1"
    local code="${2:-1}"
    log_error "${msg}"
    exit "${code}"
}

# --- require_cmd -----------------------------------------------------------
# Verify one or more commands are on PATH. Exit 1 with a clear message if
# any are missing, listing every missing one so the user does not have to
# play whack-a-mole.
require_cmd() {
    local missing=()
    local cmd
    for cmd in "$@"; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            missing+=("${cmd}")
        fi
    done
    if ((${#missing[@]} > 0)); then
        die "missing required command(s): ${missing[*]}"
    fi
}

# --- retry -----------------------------------------------------------------
# Usage: retry <attempts> <base_sleep_seconds> -- <cmd> [args...]
#
# Runs the command, retrying on non-zero exit up to <attempts> times.
# Sleep between attempts uses exponential backoff:
#   sleep = base_sleep * 2^(attempt-1)
# so with base_sleep=1 and attempts=5: sleeps 1, 2, 4, 8 between tries.
#
# Returns the last command's exit code on final failure, 0 on success.
retry() {
    if (($# < 4)); then
        die "retry: usage: retry <attempts> <base_sleep> -- <cmd> [args...]" 2
    fi
    local attempts="$1" base_sleep="$2"
    shift 2
    if [[ "$1" != "--" ]]; then
        die "retry: expected '--' before the command, got '$1'" 2
    fi
    shift

    local attempt=1 rc=0 sleep_for
    while ((attempt <= attempts)); do
        if "$@"; then
            return 0
        fi
        rc=$?
        if ((attempt == attempts)); then
            log_error "retry: command failed after ${attempts} attempt(s): $*"
            return "${rc}"
        fi
        sleep_for=$((base_sleep * (2 ** (attempt - 1))))
        log_warn "retry: attempt ${attempt}/${attempts} failed (rc=${rc}); sleeping ${sleep_for}s"
        sleep "${sleep_for}"
        attempt=$((attempt + 1))
    done
}

# --- mktempdir_trap --------------------------------------------------------
# Create a temp directory and register an EXIT trap to remove it. Prints
# the directory path to stdout so the caller can capture it:
#
#   tmpdir="$(mktempdir_trap mockaccel-build)"
#
# Multiple calls in the same script are safe; each registers its own
# cleanup. The trap appends rather than overwrites any existing EXIT trap.
mktempdir_trap() {
    local prefix="${1:-mockaccel}"
    local dir
    dir="$(mktemp -d -t "${prefix}.XXXXXX")"

    # Preserve any pre-existing EXIT trap by appending to it.
    local existing
    existing="$(trap -p EXIT | sed -E "s/^trap -- '(.*)' EXIT$/\\1/")"
    if [[ -n "${existing}" ]]; then
        # shellcheck disable=SC2064  # we want $dir expanded now, not at trap time
        trap "${existing}; rm -rf -- '${dir}'" EXIT
    else
        # shellcheck disable=SC2064
        trap "rm -rf -- '${dir}'" EXIT
    fi

    printf '%s\n' "${dir}"
}

# --- repo_root -------------------------------------------------------------
# Print the absolute path to the repo root. Prefers `git rev-parse` so it
# works from any subdirectory and respects worktrees. Falls back to walking
# up from this file's location, which is two levels above scripts/lib/.
repo_root() {
    local root
    if root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
        printf '%s\n' "${root}"
        return 0
    fi
    # Fallback: this file lives at <repo>/scripts/lib/common.sh
    local here
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    printf '%s\n' "${here}"
}

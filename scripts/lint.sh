#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# scripts/lint.sh
#
# Lints every shell script under scripts/ with:
#   - shellcheck -x   static analysis (follows `source` directives)
#   - shfmt -d        formatting check; diff-only by default, --fix to apply
#
# This is the single source of truth that Stage 6 CI (.gitlab-ci.yml,
# Jenkinsfile) and Stage 8 pre-commit hooks will both invoke. Logic
# lives here, not in YAML and not in pre-commit config.
#
# Exit codes:
#   0   all checks passed
#   1   generic failure
#   2   usage error
#   64  shellcheck found issues
#   65  shfmt found formatting drift (run with --fix to apply)

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# --- usage -----------------------------------------------------------------
usage() {
    cat <<'EOF'
Usage: lint.sh [--fix] [--no-shellcheck] [--no-shfmt] [--help]

Runs shellcheck and shfmt across every *.sh file under scripts/.

Options:
  --fix             Apply shfmt formatting in place. Default is diff-only.
  --no-shellcheck   Skip shellcheck.
  --no-shfmt        Skip shfmt.
  -h, --help        Show this help and exit.

Formatting rules (shfmt):
  -i 4     4-space indent
  -ci      indent switch cases
  -bn      binary ops at start of next line in long expressions

Exit codes:
  0   all checks passed
  2   usage error
  64  shellcheck failed
  65  shfmt found formatting drift
EOF
}

# --- defaults --------------------------------------------------------------
do_fix=0
run_shellcheck=1
run_shfmt=1

# --- arg parsing -----------------------------------------------------------
while (($# > 0)); do
    case "$1" in
        --fix) do_fix=1 ;;
        --no-shellcheck) run_shellcheck=0 ;;
        --no-shfmt) run_shfmt=0 ;;
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

# --- file discovery --------------------------------------------------------
collect_files() {
    # Emits filenames null-delimited so the caller can read them safely
    # via `while read -r -d ''`. Avoids `mapfile`, which is bash 4.0+
    # and missing from macOS's stock bash 3.2.
    find "${SCRIPT_DIR}" -type f -name '*.sh' -print0 | sort -z
}

# --- main ------------------------------------------------------------------
main() {
    local -a files=()
    local f
    while IFS= read -r -d '' f; do
        files+=("${f}")
    done < <(collect_files)

    if ((${#files[@]} == 0)); then
        die "lint: no shell files found under ${SCRIPT_DIR}" 1
    fi

    log_step "lint: ${#files[@]} file(s) under scripts/"
    for f in "${files[@]}"; do
        log_info "  ${f#"$(repo_root)"/}"
    done

    local sc_rc=0 sf_rc=0

    if ((run_shellcheck == 1)); then
        log_step "lint: shellcheck"
        require_cmd shellcheck
        # -x: follow `source` directives so common.sh is checked in context.
        # -P SCRIPTDIR: resolve relative source paths against each script's
        #   own directory, not shellcheck's cwd. Without this, the
        #   `# shellcheck source=lib/common.sh` hints emit SC1091 when
        #   lint.sh is invoked from anywhere other than scripts/.
        # We pass every file in one invocation so shellcheck can resolve
        # cross-file references.
        if ! shellcheck -x -P SCRIPTDIR "${files[@]}"; then
            sc_rc=64
            log_error "lint: shellcheck reported issues"
        fi
    else
        log_warn "lint: shellcheck skipped (--no-shellcheck)"
    fi

    if ((run_shfmt == 1)); then
        log_step "lint: shfmt"
        require_cmd shfmt
        # Flags must match scripts/README.md "Conventions" section:
        #   -i 4   indent with 4 spaces
        #   -ci    indent switch cases
        #   -bn    binary ops at start of next line
        local -a shfmt_args=(-i 4 -ci -bn)
        if ((do_fix == 1)); then
            log_info "lint: applying formatting in place (--fix)"
            if ! shfmt -w "${shfmt_args[@]}" "${files[@]}"; then
                sf_rc=65
                log_error "lint: shfmt failed while rewriting files"
            fi
        else
            # -d emits a unified diff for any drift and exits non-zero
            # if anything would change. Perfect for CI.
            if ! shfmt -d "${shfmt_args[@]}" "${files[@]}"; then
                sf_rc=65
                log_error "lint: shfmt found formatting drift (run with --fix to apply)"
            fi
        fi
    else
        log_warn "lint: shfmt skipped (--no-shfmt)"
    fi

    # Report a single, stable exit code. Prefer shellcheck's code if both
    # failed, so CI logs surface the more actionable failure first.
    if ((sc_rc != 0)); then
        exit "${sc_rc}"
    fi
    if ((sf_rc != 0)); then
        exit "${sf_rc}"
    fi

    log_step "lint: done"
    log_info "all checks passed"
}

main "$@"

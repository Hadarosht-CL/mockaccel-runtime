<!-- SPDX-License-Identifier: Apache-2.0 -->

# scripts/

Small Bash library that owns every action CI (Continuous Integration) needs to perform on this repo: bootstrap a host, build the SUT (System Under Test), run tests, package artifacts, cut releases, and lint the scripts themselves.

The same scripts are called both from a developer's shell and from CI pipelines (GitLab CI in Stage 6, Jenkins in Stage 6). Logic lives here, not in YAML or Groovy. If a CI job's `script:` block grows past one line, that logic belongs in a new function in `lib/common.sh` or in a new verb script here.

## Layout

```
scripts/
  README.md          This file.
  lib/
    common.sh        Shared helpers: logging, die, require_cmd, retry, temp cleanup, repo_root.
  bootstrap.sh       Install host toolchain on Ubuntu/Debian. Idempotent.
  build.sh           Configure + build via CMake/Ninja.
  test.sh            Run all registered test suites.
  package.sh         Produce distributable artifacts (stub until Stage 7).
  release.sh         Tag-driven release flow (stub until Stage 10).
  lint.sh            Run shellcheck and shfmt across scripts/.
  publish.sh	     Push artifacts to Artifactory (stub until Stage 7).
  deploy.sh	     Deploy via Helm to k3s (stub until Stage 9).
```

The call graph CI follows is linear:

```
bootstrap.sh  ->  build.sh  ->  test.sh  ->  package.sh  ->  release.sh
```

`lint.sh` is orthogonal: it runs on every push, before `build.sh`.

## Conventions

Every script in this directory satisfies all of the following. `lint.sh` enforces the mechanical ones.

1. **SPDX header.** First non-shebang line is `# SPDX-License-Identifier: Apache-2.0`.
2. **Shebang.** `#!/usr/bin/env bash` - portable, picks up the user's bash from PATH.
3. **Strict mode.** First executable line is:
   ```bash
   set -Eeuo pipefail
   IFS=$'\n\t'
   ```
   - `-E` makes ERR traps inherit into functions and subshells.
   - `-e` exits on any unhandled non-zero return.
   - `-u` treats unset variables as errors.
   - `-o pipefail` makes a pipeline fail if any stage fails, not just the last.
   - `IFS` reset prevents word-splitting surprises on filenames with spaces.
4. **Source the library, do not re-implement.** Every verb script does:
   ```bash
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   # shellcheck source=lib/common.sh
   source "${SCRIPT_DIR}/lib/common.sh"
   ```
5. **One verb per file.** `build.sh` builds. It does not also test. Composition happens in CI, not inside a script.
6. **`--help` on every script.** Print usage to stdout and exit 0 when invoked with `-h` or `--help`.
7. **Meaningful exit codes.** `0` success, `1` generic failure, `2` usage error, `64+` reserved for verb-specific failures documented in that script's `--help`.
8. **Idempotent where it can be.** `bootstrap.sh` re-runs without harm. `build.sh --clean` is the explicit destructive form.
9. **No `cd` without restoring.** Use `pushd`/`popd` or subshells. The library's `repo_root` helper lets a script find its anchor without `cd`-ing.
10. **`shellcheck -x`-clean and `shfmt -d -i 4 -ci -bn`-clean.** `lint.sh` is the source of truth for both.

## Where Bash stops and Python starts

A line we hold deliberately:

- **Bash** owns environment plumbing: invoking compilers, moving files, calling other tools, looping over a known short list of shell commands.
- **Python** owns logic with data structures: parsing JSON, modeling test fixtures, anything that would want a dict, a class, or types.

If a script is reaching for `awk`/`sed` to parse structured output, that is the signal to write a small Python helper and call it from the script instead.

## Platform support

These scripts target Ubuntu/Debian Linux because that is what CI runners use. macOS is supported on a best-effort basis for local development; `bootstrap.sh` will refuse to run on macOS and tell the developer to install `cmake`, `ninja`, `shellcheck`, and `shfmt` via Homebrew manually.

## How to add a new verb

1. Decide it really is a new verb, not a flag on an existing one. Cross-compilation is a flag on `build.sh`, not `cross_build.sh`.
2. Copy an existing script as a template so you inherit the strict-mode preamble.
3. Add the SPDX header, shebang, strict mode, library source, `--help` block.
4. Add a row to the Layout table above.
5. Make sure `lint.sh` passes.
6. Reference it from `.gitlab-ci.yml` and `Jenkinsfile` (Stage 6) as a one-line `script:` entry.

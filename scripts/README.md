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
  package.sh         Build the SUT Docker image (--target=host). aarch64 path arrives in Stage 7 Step 3.
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

## Cross-compiling to aarch64

Build the C++ pieces of the SUT for 64-bit ARM Linux from any x86_64 host. The Python bindings are intentionally not cross-compiled - they are forced off by `build.sh --target=aarch64`.

The one command:

```bash
./scripts/build.sh --target=aarch64
```

Output lands in `build-aarch64/` (the host build keeps using `build/`, so the two can coexist). The daemon binary is at `build-aarch64/device_simulator/mockaccel_device_simulator`.

### Prerequisites - native Linux host

On Debian or Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    g++-aarch64-linux-gnu qemu-user-static file
```

What each package gives you:

- `g++-aarch64-linux-gnu` - the cross-compiler itself. CMake's toolchain file at `cmake/toolchains/aarch64-linux-gnu.cmake` calls into it.
- `qemu-user-static` - user-mode QEMU. Lets you actually run the resulting ARM binary on an x86_64 host without booting a full ARM VM (Virtual Machine).
- `file` - identifies the produced binary's architecture so you can prove the build did what you think it did.

### Prerequisites - macOS host

Apple does not package `aarch64-linux-gnu-gcc`. Run the cross-build inside the project's standard Docker container instead:

```bash
docker run --rm -t \
    -v "$(pwd):/repo" -v /repo/build -v /repo/build-aarch64 \
    -w /repo ubuntu:22.04 \
    bash -lc '
        apt-get update -qq &&
        apt-get install -y --no-install-recommends \
            build-essential cmake ninja-build ca-certificates git \
            g++-aarch64-linux-gnu qemu-user-static file &&
        ./scripts/build.sh --target=aarch64 &&
        file build-aarch64/device_simulator/mockaccel_device_simulator &&
        qemu-aarch64-static build-aarch64/device_simulator/mockaccel_device_simulator --version
    '
```

The two anonymous-volume mounts (`-v /repo/build` and `-v /repo/build-aarch64`) mask the host's build directories so a container-side CMakeCache.txt does not poison your host build, and vice versa. Same trick the Stage 2 acceptance command uses for `.venv/` and `build/`.

### What success looks like

```bash
$ file build-aarch64/device_simulator/mockaccel_device_simulator
build-aarch64/device_simulator/mockaccel_device_simulator: ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux-aarch64.so.1, ...
```

The two parts that matter: `ELF 64-bit LSB executable` and `ARM aarch64`. If `file` prints `x86-64` anywhere on that line, the cross-build silently fell back to the host compiler - see troubleshooting below.

### Smoke-run under QEMU

```bash
qemu-aarch64-static build-aarch64/device_simulator/mockaccel_device_simulator --version
```

`--version` is the safest smoke target: the daemon prints a version line and exits immediately, no socket, no model, no telemetry. If QEMU can load the ELF, resolve the ARM dynamic linker, and run user code far enough to hit the version-print branch, the binary is genuinely runnable.

QEMU user-mode is Linux-only (or Docker-on-anything). macOS-native cannot run a Linux ARM ELF, even with QEMU installed via Homebrew - QEMU user-mode emulates a CPU, not a kernel.

### Troubleshooting

**`aarch64-linux-gnu-g++: command not found`**

You are missing the cross-compiler. On Linux, install `g++-aarch64-linux-gnu` (see Prerequisites above). On macOS, you cannot install it natively - use the Docker invocation instead.

**`file` says the binary is `x86-64`, not `ARM aarch64`**

The toolchain file was not honored. Most likely you ran raw `cmake` without `-DCMAKE_TOOLCHAIN_FILE=...` and built a host binary into `build-aarch64/` by accident. Always go through `./scripts/build.sh --target=aarch64` - it sets the toolchain flag, the Python-off flag, and the build dir together.

If you did use `build.sh --target=aarch64` and still got an x86_64 binary, delete `build-aarch64/` (CMake caches the configured compiler from the first configure) and re-run with `--clean`:

```bash
./scripts/build.sh --target=aarch64 --clean
```

**`qemu-aarch64-static: ... No such file or directory`** on a binary that clearly exists

QEMU is reporting that the *dynamic linker* the ARM binary asks for (`/lib/ld-linux-aarch64.so.1`) is missing on the host running QEMU. The Debian/Ubuntu `g++-aarch64-linux-gnu` package pulls in `libc6-arm64-cross` automatically, which provides that linker under `/usr/aarch64-linux-gnu/`. If you are running QEMU outside the apt-installed environment (a slim alpine container, a stripped-down sysroot), install `libc6-arm64-cross` or use the Docker invocation above, which has it.

## Packaging the SUT as a Docker image

`package.sh` wraps `docker build` so CI and local development share one entry point. The script also locks in a fixed tag scheme that the publish step (Stage 7 Step 4) reads back when pushing to the registry.

The one command:

```bash
./scripts/package.sh --target=host
```

--target=host builds the amd64 image using the multi-stage `Dockerfile` at the repo root (added in Stage 7 Step 1). The resulting image is tagged `mockaccel-runtime:dev-amd64-<short-sha>`, where `<short-sha>` comes from `git rev-parse --short HEAD`. If the script is invoked outside a git checkout, the SHA placeholder is the literal string `unknown` and the rest of the script still works.

--target=aarch64 is intentionally a stub in Step 2 and returns exit 67. The real aarch64 image path lands in Step 3 alongside the Dockerfile's TARGETARCH build-arg extension.

Prerequisites
Docker must be installed and the daemon reachable. require_cmd docker fails fast otherwise. No other host tooling beyond what the Dockerfile's builder stage installs itself.

Verifying a freshly packaged image

```bash
# List what package.sh just tagged.
docker images mockaccel-runtime --format '{{.Repository}}:{{.Tag}}'

# Smoke-run the image - same daemon as Stage 7 Step 1, new tag.
docker run --rm mockaccel-runtime:dev-amd64-<short-sha> --version
```

## Tag scheme

`mockaccel-runtime:dev-<arch>-<short-sha>`

- `<arch>`: amd64 for --target=host, arm64 for --target=aarch64. The script maps the wrapper-internal target name (host / aarch64, matching build.sh) to the Docker-world arch name in one place so the rest of the script does not have to think about the distinction.
- `<short-sha>`: 7-character git SHA of HEAD, or unknown when not in a git checkout.

Stage 7 Step 4 extends this scheme with additional moving tags - latest on main pushes, `v<semver>` on tag pushes. The `dev-` prefix stays as the everyday CI tag so reviewers can tell at a glance whether an image came from a feature branch or a release.

Exit codes
0 success.
2 usage error (missing or invalid --target).
64 docker build failed.
65 reserved - missing cross artifact for the aarch64 path (lands in Step 3).
67 --target=aarch64 reached this stub. Lands in Step 3.

### After pasting

Run the verification block again - the markdown is plain prose, no fences inside fences, so lint should still be green. Then stage the README file alongside `package.sh`:

```bash
git add scripts/README.md
git diff --cached --stat
# Expect both scripts/package.sh and scripts/README.md.

## How to add a new verb

1. Decide it really is a new verb, not a flag on an existing one. Cross-compilation is a flag on `build.sh`, not `cross_build.sh`.
2. Copy an existing script as a template so you inherit the strict-mode preamble.
3. Add the SPDX header, shebang, strict mode, library source, `--help` block.
4. Add a row to the Layout table above.
5. Make sure `lint.sh` passes.
6. Reference it from `.gitlab-ci.yml` and `Jenkinsfile` (Stage 6) as a one-line `script:` entry.

# SPDX-License-Identifier: Apache-2.0
#
# cmake/toolchains/aarch64-linux-gnu.cmake
#
# CMake toolchain file for cross-compiling to 64-bit ARM Linux
# (aarch64) from an x86_64 Linux host using the GNU cross-toolchain
# packaged as `gcc-aarch64-linux-gnu` / `g++-aarch64-linux-gnu` on
# Debian and Ubuntu.
#
# Usage:
#   cmake -S . -B build-aarch64 \
#         -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/aarch64-linux-gnu.cmake \
#         -DCMAKE_BUILD_TYPE=Release \
#         -DMOCKACCEL_BUILD_PYTHON=OFF
#
# scripts/build.sh --target=aarch64 wraps this so callers do not
# have to remember the flag set.
#
# Notes:
#   - Python bindings are intentionally not cross-compiled in this
#     project (see Stage 4 of the project overview). Pass
#     -DMOCKACCEL_BUILD_PYTHON=OFF or use scripts/build.sh.
#   - The compiler triple can be overridden by setting
#     MOCKACCEL_AARCH64_TRIPLE before the first cmake configure,
#     e.g. for a Yocto SDK whose tools are not named
#     `aarch64-linux-gnu-*`.

# Target system identity. CMAKE_SYSTEM_NAME being set is what flips
# CMake into cross-compile mode; CMAKE_CROSSCOMPILING then evaluates
# true for the rest of the configure.
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

# Compiler triple. Overridable so a different cross-toolchain layout
# (Yocto, Buildroot, vendor SDK) can reuse this file by exporting
# MOCKACCEL_AARCH64_TRIPLE before configure.
if(NOT DEFINED MOCKACCEL_AARCH64_TRIPLE)
    set(MOCKACCEL_AARCH64_TRIPLE "aarch64-linux-gnu")
endif()

set(CMAKE_C_COMPILER   "${MOCKACCEL_AARCH64_TRIPLE}-gcc")
set(CMAKE_CXX_COMPILER "${MOCKACCEL_AARCH64_TRIPLE}-g++")
set(CMAKE_AR           "${MOCKACCEL_AARCH64_TRIPLE}-ar")
set(CMAKE_RANLIB       "${MOCKACCEL_AARCH64_TRIPLE}-ranlib")
set(CMAKE_STRIP        "${MOCKACCEL_AARCH64_TRIPLE}-strip")

# Sysroot for the cross-toolchain as packaged by Debian/Ubuntu.
# CMAKE_FIND_ROOT_PATH tells the find_* commands where to look for
# libraries and headers when cross-compiling.
set(CMAKE_FIND_ROOT_PATH "/usr/${MOCKACCEL_AARCH64_TRIPLE}")

# Search policy:
#   - PROGRAMS: look on the HOST (we want host tools like git, python,
#     cmake itself; not aarch64 binaries we cannot run natively).
#   - LIBRARY / INCLUDE / PACKAGE: look ONLY in the target sysroot,
#     never on the host, so we do not accidentally link the host's
#     x86_64 libs into an aarch64 binary.
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

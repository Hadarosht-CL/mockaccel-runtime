cmake_minimum_required(VERSION 3.20)
project(mockaccel_runtime
    VERSION 0.1.0
    DESCRIPTION "Mock embedded inference-accelerator runtime (test fixture / SDK practice)"
    LANGUAGES CXX
)

# --- Global build settings ---------------------------------------------------
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

add_compile_options(-Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wsign-conversion)

# --- Options ----------------------------------------------------------------
option(MOCKACCEL_BUILD_PYTHON "Build pybind11 Python bindings" ON)

# --- Third-party deps via FetchContent --------------------------------------
# Stage 8 of the learning plan: convert one of these to a git submodule
# under third_party/ as a deliberate exercise. The build supports both.
include(FetchContent)

FetchContent_Declare(
    nlohmann_json
    GIT_REPOSITORY https://github.com/nlohmann/json.git
    GIT_TAG        v3.11.3
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(nlohmann_json)

if(MOCKACCEL_BUILD_PYTHON)
    # Prefer a vendored submodule at third_party/pybind11 if present (Stage 8),
    # otherwise fetch.
    if(EXISTS "${CMAKE_SOURCE_DIR}/third_party/pybind11/CMakeLists.txt")
        message(STATUS "Using vendored pybind11 from third_party/pybind11")
        add_subdirectory(third_party/pybind11)
    else()
        FetchContent_Declare(
            pybind11
            GIT_REPOSITORY https://github.com/pybind/pybind11.git
            GIT_TAG        v2.13.6
            GIT_SHALLOW    TRUE
        )
        FetchContent_MakeAvailable(pybind11)
    endif()
endif()

# --- Subdirectories ---------------------------------------------------------
add_subdirectory(device_simulator)
add_subdirectory(runtime_core)
if(MOCKACCEL_BUILD_PYTHON)
    add_subdirectory(pymockaccel)
endif()

# --- Install rules ----------------------------------------------------------
install(DIRECTORY include/ DESTINATION include)

message(STATUS "")
message(STATUS "mockaccel_runtime ${PROJECT_VERSION}")
message(STATUS "  Build type:      ${CMAKE_BUILD_TYPE}")
message(STATUS "  C++ standard:    ${CMAKE_CXX_STANDARD}")
message(STATUS "  Python bindings: ${MOCKACCEL_BUILD_PYTHON}")
message(STATUS "  System:          ${CMAKE_SYSTEM_NAME} ${CMAKE_SYSTEM_PROCESSOR}")
message(STATUS "")

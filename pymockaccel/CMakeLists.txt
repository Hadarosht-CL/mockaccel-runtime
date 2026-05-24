# SPDX-License-Identifier: Apache-2.0

pybind11_add_module(pymockaccel
    src/bindings.cpp
)

target_link_libraries(pymockaccel
    PRIVATE
        mockaccel_runtime
)

target_include_directories(pymockaccel
    PRIVATE
        ${CMAKE_SOURCE_DIR}/include
)

set_target_properties(pymockaccel PROPERTIES
    OUTPUT_NAME pymockaccel
)

# Install into a layout that `pip install .` could pick up later.
install(TARGETS pymockaccel LIBRARY DESTINATION pymockaccel)

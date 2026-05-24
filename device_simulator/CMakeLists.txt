# SPDX-License-Identifier: Apache-2.0

add_executable(mockaccel_device_simulator
    src/main.cpp
)

target_include_directories(mockaccel_device_simulator
    PRIVATE
        ${CMAKE_SOURCE_DIR}/include
)

target_link_libraries(mockaccel_device_simulator
    PRIVATE
        nlohmann_json::nlohmann_json
)

set_target_properties(mockaccel_device_simulator PROPERTIES
    OUTPUT_NAME mockaccel_device_simulator
)

install(TARGETS mockaccel_device_simulator RUNTIME DESTINATION bin)

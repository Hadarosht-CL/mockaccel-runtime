add_library(mockaccel_runtime STATIC
    src/client.cpp
    src/device.cpp
    src/codec.cpp
)

target_include_directories(mockaccel_runtime
    PUBLIC
        ${CMAKE_SOURCE_DIR}/include
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(mockaccel_runtime
    PRIVATE
        nlohmann_json::nlohmann_json
)

set_target_properties(mockaccel_runtime PROPERTIES
    OUTPUT_NAME mockaccel_runtime
)

install(TARGETS mockaccel_runtime ARCHIVE DESTINATION lib)

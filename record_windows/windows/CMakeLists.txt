cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "record_windows")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "record_windows_plugin")

add_library(${PLUGIN_NAME} SHARED
  "record_windows.h"
  "record_windows.cpp"
  "record_windows_plugin.cpp"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

# Add SFML
set(SFML_BUILD_GRAPHICS FALSE)
set(SFML_BUILD_NETWORK FALSE)
set(SFML_BUILD_WINDOW FALSE)

include(FetchContent)

FetchContent_Declare(
 sfml
 GIT_REPOSITORY https://github.com/SFML/SFML.git
 GIT_TAG 2.5.1
)

FetchContent_MakeAvailable(sfml)
# END Add SFML

target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
  sfml-audio
  sfml-system
)

set(SFML_OPENAL_DLL_NAME "${CMAKE_CURRENT_SOURCE_DIR}/bin/openal32.dll")

# List of absolute paths to libraries that should be bundled with the plugin
set(record_windows_bundled_libraries
  ""
  $<TARGET_FILE:sfml-audio>
  $<TARGET_FILE:sfml-system>
  ${SFML_OPENAL_DLL_NAME}
  PARENT_SCOPE
)

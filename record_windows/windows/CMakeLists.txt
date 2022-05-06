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

# Add SFML
set(SFML_DIR $ENV{SFML_DIR})
find_package(SFML 2.5 COMPONENTS system audio REQUIRED)

set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
  sfml-system
  sfml-audio
)

set(SFML_AUDIO_DEBUG_DLL_NAME "${CMAKE_CURRENT_SOURCE_DIR}/bin/sfml-audio-d-2.dll")
set(SFML_SYSTEM_DEBUG_DLL_NAME "${CMAKE_CURRENT_SOURCE_DIR}/bin/sfml-system-d-2.dll")
set(SFML_AUDIO_DLL_NAME "${CMAKE_CURRENT_SOURCE_DIR}/bin/sfml-audio-2.dll")
set(SFML_SYSTEM_DLL_NAME "${CMAKE_CURRENT_SOURCE_DIR}/bin/sfml-system-2.dll")
set(SFML_OPENAL_DLL_NAME "${CMAKE_CURRENT_SOURCE_DIR}/bin/openal32.dll")

# List of absolute paths to libraries that should be bundled with the plugin
set(record_windows_bundled_libraries
  ""
  ${SFML_AUDIO_DEBUG_DLL_NAME}
  ${SFML_SYSTEM_DEBUG_DLL_NAME}
  ${SFML_AUDIO_DLL_NAME}
  ${SFML_SYSTEM_DLL_NAME}
  ${SFML_OPENAL_DLL_NAME}
  PARENT_SCOPE
)

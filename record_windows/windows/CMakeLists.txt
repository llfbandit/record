# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.23)

# Project-level configuration.
set(PROJECT_NAME "record_windows")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "record_windows_plugin")

# Any new source files that you add to the plugin should be added here.
list(APPEND PLUGIN_SOURCES
  "record_windows_plugin.cpp"
  "record_windows_plugin.h"
  "record_config.h"
  "record_config.cpp"
  "platform_thread.h"
  "platform_thread.cpp"
  "recorder_dispatcher.h"
  "recorder_wrapper.h"
  "recorder_wrapper.cpp"
  "record/record.h"
  "record/record.cpp"
  "record/record_readercallback.cpp"
  "record/reader_callback.h"
  "record/reader_callback.cpp"
  "record/capture_engine.h"
  "record/capture_engine.cpp"
  "record/timeline_clock.h"
  "record/sink/record_sink.h"
  "record/sink/file_sink.h"
  "record/sink/file_sink.cpp"
  "record/sink/stream_sink.h"
  "record/sink/stream_sink.cpp"
  "encoder/stream_encoder.h"
  "encoder/codec_caps.h"
  "encoder/codec_caps.cpp"
  "encoder/aac_adts_encoder.h"
  "encoder/aac_adts_encoder.cpp"
  "encoder/pcm_encoder.h"
  "encoder/pcm_encoder.cpp"
  "mediatype/record_mediatype.h"
  "mediatype/record_mediatype.cpp"
  "audio_device/record_audio_device.h"
  "audio_device/record_audio_device.cpp"
  "device_notification/device_notification_client.h"
  "device_notification/device_notification_client.cpp"
  "amplitude/amplitude_tracker.h"
  "amplitude/amplitude_tracker.cpp"
  "utils.h"
  "event_stream_handler.h"
)

# Define the plugin library target. Its name must not be changed (see comment
# on PLUGIN_NAME above).
add_library(${PLUGIN_NAME} SHARED
  "include/record_windows/record_windows_plugin_c_api.h"
  "record_windows_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

set(wmf_libs mf.lib mfplat.lib mfreadwrite.lib mfuuid.lib Shlwapi.lib ole32.lib)

# Apply a standard set of build settings that are configured in the
# application-level CMakeLists.txt. This can be removed for plugins that want
# full control over build settings.
apply_standard_settings(${PLUGIN_NAME})

# Symbols are hidden by default to reduce the chance of accidental conflicts
# between plugins. This should not be removed; any symbols that should be
# exported should be explicitly exported with the FLUTTER_PLUGIN_EXPORT macro.
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

# Source include directories and library dependencies. Add any plugin-specific
# dependencies here.
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin ${wmf_libs})



# === Tests ===
# Off in app builds. Configure the example with -Dinclude_record_windows_tests=ON
# and build the record_windows_test target.
if (include_${PROJECT_NAME}_tests)
  set(TEST_RUNNER "${PROJECT_NAME}_test")
  enable_testing()

  include(FetchContent)
  FetchContent_Declare(
    googletest
    URL https://github.com/google/googletest/archive/refs/tags/v1.15.2.zip
    URL_HASH SHA256=f179ec217f9b3b3f3c6e8b02d3e7eda997b49e4ce26d6b235c9053bec9c0bf9f
    # Date the extracted files now, so a new URL rebuilds them.
    DOWNLOAD_EXTRACT_TIMESTAMP FALSE
  )
  # Match the plugin's CRT.
  set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
  # Its install rules otherwise join the bundle step and fail it.
  set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
  # Nothing here mocks anything.
  set(BUILD_GMOCK OFF CACHE BOOL "" FORCE)
  FetchContent_MakeAvailable(googletest)

  # Build gtest only when the test runner links it.
  set_target_properties(gtest gtest_main PROPERTIES EXCLUDE_FROM_ALL TRUE)

  # Build the plugin sources straight in, outside the default build: the C API can't be unit tested.
  add_executable(${TEST_RUNNER} EXCLUDE_FROM_ALL
    "test/recorder_dispatcher_test.cpp"
    "test/platform_thread_test.cpp"
    "test/reader_callback_test.cpp"
    "test/recorder_wrapper_test.cpp"
    "test/recorder_stop_test.cpp"
    "test/record_config_test.cpp"
    "test/timeline_clock_test.cpp"
    "test/sink_test.cpp"
    "test/device_notification_client_test.cpp"
    "test/recorder_route_change_test.cpp"
    "test/recorder_reattach_test.cpp"
    "test/recorder_test_support.h"
    "test/fake_capture_engine.h"
    ${PLUGIN_SOURCES}
  )

  apply_standard_settings(${TEST_RUNNER})
  target_include_directories(${TEST_RUNNER} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
  target_link_libraries(${TEST_RUNNER} PRIVATE flutter flutter_wrapper_plugin gtest_main ${wmf_libs})

  # flutter_wrapper_plugin links against the Flutter DLL.
  add_custom_command(TARGET ${TEST_RUNNER} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${FLUTTER_LIBRARY}" $<TARGET_FILE_DIR:${TEST_RUNNER}>
  )

  include(GoogleTest)
  gtest_discover_tests(${TEST_RUNNER})
endif()

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(record_windows_bundled_libraries
  ""
  PARENT_SCOPE
)

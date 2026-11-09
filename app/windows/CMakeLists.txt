# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(dnet LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "dnet")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# The Rust core: identity, encryption and storage. Cargo builds it and it
# ships beside the executable. Cargo must be on PATH.
set(DNET_CORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../core")
set(DNET_CORE_LIBRARY "${DNET_CORE_DIR}/target/release/dnet_core.dll")
add_custom_target(dnet_core ALL
  COMMAND cargo build --release --lib --manifest-path "${DNET_CORE_DIR}/Cargo.toml"
  BYPRODUCTS "${DNET_CORE_LIBRARY}"
  COMMENT "Building the DNet core"
  VERBATIM)
add_dependencies(${BINARY_NAME} dnet_core)

# Bluetooth for Windows: finds nearby devices and moves sealed frames. It is
# a library of its own so that the core holds no radio code.
set(DNET_RADIO_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../radio_windows")
set(DNET_RADIO_LIBRARY "${DNET_RADIO_DIR}/target/release/dnet_radio.dll")
add_custom_target(dnet_radio ALL
  COMMAND cargo build --release --lib --manifest-path "${DNET_RADIO_DIR}/Cargo.toml"
  BYPRODUCTS "${DNET_RADIO_LIBRARY}"
  COMMENT "Building the DNet Windows radio"
  VERBATIM)
add_dependencies(${BINARY_NAME} dnet_radio)


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# The executable and everything it needs are put together in one folder.
# A release build goes straight into dist\DNet-Windows at the top of the
# repository, the one place finished builds go, and that folder is emptied
# first so nothing from an older build stays in it. Debug and Profile builds
# go next to their executable, where Flutter runs them from.
get_filename_component(DNET_DIST_DIR
  "${CMAKE_CURRENT_SOURCE_DIR}/../../dist/DNet-Windows" ABSOLUTE)
set(BUILD_BUNDLE_DIR
  "$<IF:$<CONFIG:Release>,${DNET_DIST_DIR},$<TARGET_FILE_DIR:${BINARY_NAME}>>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)

set(INSTALL_BUNDLE_DATA_DIR "${BUILD_BUNDLE_DIR}/data")
set(INSTALL_BUNDLE_LIB_DIR "${BUILD_BUNDLE_DIR}")

install(CODE "
  if(\"\${CMAKE_INSTALL_CONFIG_NAME}\" STREQUAL \"Release\")
    file(REMOVE_RECURSE \"${DNET_DIST_DIR}\")
  endif()
  " COMPONENT Runtime)

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${BUILD_BUNDLE_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

install(FILES "${DNET_CORE_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

install(FILES "${DNET_RADIO_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# The Visual C++ runtime (msvcp140.dll, vcruntime140.dll, ...), copied
# beside the executable so the app starts on a PC that has never had the
# Visual C++ Redistributable installed. The executable, the core and the
# radio library all need it. The Universal CRT is part of Windows 10 and
# later, so it is left out.
set(CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS_SKIP TRUE)
set(CMAKE_INSTALL_UCRT_LIBRARIES FALSE)
include(InstallRequiredSystemLibraries)
if(CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS)
  install(PROGRAMS ${CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS}
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    CONFIGURATIONS Profile;Release
    COMPONENT Runtime)
else()
  message(WARNING "The Visual C++ runtime was not found; the Windows app "
    "will need the Visual C++ Redistributable installed to start.")
endif()

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)

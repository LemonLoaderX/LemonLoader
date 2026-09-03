cmake_minimum_required(VERSION 3.22)

project(LemonLoaderAndroidBootstrap LANGUAGES C CXX ASM)

if(NOT ANDROID)
    message(FATAL_ERROR "The NDK bootstrap must be built with the Android toolchain")
endif()

set(LEMON_DOBBY_SOURCE_DIR "" CACHE PATH "Path to the LemonLoader Dobby source repository")
if(NOT EXISTS "${LEMON_DOBBY_SOURCE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "Set LEMON_DOBBY_SOURCE_DIR to the complete LemonLoader Dobby source repository")
endif()

set(DOBBY_DEBUG OFF CACHE BOOL "" FORCE)
add_subdirectory("${LEMON_DOBBY_SOURCE_DIR}" "${CMAKE_BINARY_DIR}/dependencies/dobby" EXCLUDE_FROM_ALL)

add_library(plthook STATIC third_party/plthook/plthook_elf.c)
target_include_directories(plthook PUBLIC third_party/plthook)

add_library(main SHARED
    src/arm64_value_return.S
    src/arm64_il2cpp_resolver.cpp
    src/android_crypto.cpp
    src/android_environment.cpp
    src/deployment_policy.hpp
    src/bootstrap.cpp
    src/logging.cpp
    src/runtime.cpp)

target_compile_features(main PRIVATE cxx_std_17)
target_compile_options(main PRIVATE
    -fvisibility=hidden
    -fvisibility-inlines-hidden
    -Wall
    -Wextra
    -Werror=return-type)

target_include_directories(main PRIVATE include src third_party/plthook)
target_link_libraries(main PRIVATE android log dl dobby_static plthook)
target_link_options(main PRIVATE
    -Wl,--no-undefined
    -Wl,-z,max-page-size=16384
    -Wl,-z,common-page-size=16384)

set_target_properties(main PROPERTIES
    OUTPUT_NAME main
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED YES)

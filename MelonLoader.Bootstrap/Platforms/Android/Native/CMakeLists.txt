cmake_minimum_required(VERSION 3.22)

project(LemonLoaderAndroidBootstrap LANGUAGES C CXX ASM)

if(NOT ANDROID)
    message(FATAL_ERROR "The NDK bootstrap must be built with the Android toolchain")
endif()

set(LEMON_DOBBY_SOURCE_DIR "" CACHE PATH "Path to the LemonLoader Dobby source repository")
if(NOT EXISTS "${LEMON_DOBBY_SOURCE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "Set LEMON_DOBBY_SOURCE_DIR to the complete LemonLoader Dobby source repository")
endif()

# Keep local checkout/toolchain paths out of debug inputs to the linker build ID.
add_compile_options(
    "-ffile-prefix-map=${CMAKE_SOURCE_DIR}=/src/LemonLoader/AndroidNative"
    "-ffile-prefix-map=${CMAKE_BINARY_DIR}=/build/LemonLoader/AndroidNative"
    "-ffile-prefix-map=${LEMON_DOBBY_SOURCE_DIR}=/src/Dobby"
    "-ffile-prefix-map=${CMAKE_ANDROID_NDK}=/toolchain/android-ndk")

set(DOBBY_DEBUG OFF CACHE BOOL "" FORCE)
add_subdirectory("${LEMON_DOBBY_SOURCE_DIR}" "${CMAKE_BINARY_DIR}/dependencies/dobby" EXCLUDE_FROM_ALL)

add_library(plthook STATIC third_party/plthook/plthook_elf.c)
target_include_directories(plthook PUBLIC third_party/plthook)

add_library(main SHARED
    src/arm64_value_return.S
    src/arm64_il2cpp_resolver.cpp
    src/android_crypto.cpp
    src/android_environment.cpp
    src/android_assets.cpp
    src/android_payload.cpp
    src/android_deployment.cpp
    src/deployment_policy.hpp
    src/bootstrap.cpp
    src/logging.cpp
    src/system_exit.cpp
    src/runtime.cpp)

set(LEMON_CRYPTO_DEX "" CACHE FILEPATH "Validated runtime pack crypto helper DEX")
if(LEMON_CRYPTO_DEX)
    if(ANDROID_PLATFORM_LEVEL LESS 26)
        message(FATAL_ERROR "Embedded crypto requires Android API 26 or later")
    endif()
    if(NOT EXISTS "${LEMON_CRYPTO_DEX}")
        message(FATAL_ERROR "Crypto helper DEX does not exist")
    endif()
    file(TO_CMAKE_PATH "${LEMON_CRYPTO_DEX}" LEMON_CRYPTO_DEX)
    file(SHA256 "${LEMON_CRYPTO_DEX}" LEMON_CRYPTO_DEX_SHA256)
    configure_file(src/crypto_dex.S.in "${CMAKE_CURRENT_BINARY_DIR}/crypto_dex.S" @ONLY)
    set_source_files_properties("${CMAKE_CURRENT_BINARY_DIR}/crypto_dex.S"
        PROPERTIES OBJECT_DEPENDS "${LEMON_CRYPTO_DEX}")
    target_sources(main PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/crypto_dex.S")
    target_compile_definitions(main PRIVATE LEMON_EMBEDDED_CRYPTO_DEX=1)
endif()

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

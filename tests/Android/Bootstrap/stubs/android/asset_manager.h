#pragma once
#include <cstddef>
#include <cstdint>
struct AAssetManager {};
struct AAsset {};
constexpr int AASSET_MODE_STREAMING = 2;
AAsset* AAssetManager_open(AAssetManager*, const char*, int);
int AAsset_read(AAsset*, void*, size_t);
int64_t AAsset_getLength64(AAsset*);
void AAsset_close(AAsset*);

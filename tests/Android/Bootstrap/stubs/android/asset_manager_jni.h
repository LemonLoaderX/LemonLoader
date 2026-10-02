#pragma once
#include "asset_manager.h"
#include <jni.h>
AAssetManager* AAssetManager_fromJava(JNIEnv*, jobject);

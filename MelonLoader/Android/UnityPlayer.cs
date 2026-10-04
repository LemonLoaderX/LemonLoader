#if ANDROID
#nullable enable
using System;
using Java.Interop;

namespace MelonLoader.Android;

public static class UnityPlayer
{
    /// <summary>Returns a new owned peer for the current Activity; reacquire after Activity recreation.</summary>
    public static AndroidActivity? CurrentActivity => JavaBinding.GetStaticField<AndroidActivity>(
        "com/unity3d/player/UnityPlayer", "currentActivity");
}
#endif

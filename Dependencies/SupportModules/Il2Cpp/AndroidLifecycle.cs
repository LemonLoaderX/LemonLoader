#if ANDROID

using System.Reflection;
using UnityEngine.SceneManagement;

namespace MelonLoader.Support
{
    internal static class AndroidLifecycle
    {
        private const BindingFlags StaticMethodFlags =
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static;

        private static bool _initialized;

        internal static void Init()
        {
            if (_initialized)
                return;

            _initialized = true;

            MethodInfo sceneLoaded = typeof(SceneManager).GetMethod("Internal_SceneLoaded", StaticMethodFlags);
            MethodInfo sceneUnloaded = typeof(SceneManager).GetMethod("Internal_SceneUnloaded", StaticMethodFlags);
            SceneHandler.Init(sceneLoaded, sceneUnloaded);
        }
    }
}

#endif

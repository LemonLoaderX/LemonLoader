using System;
using UnityEngine.SceneManagement;
using System.Collections.Generic;
using HarmonyLib;
using System.Reflection;
#if ANDROID
using Il2CppInterop.Runtime;
#endif

#pragma warning disable CA2013

namespace MelonLoader.Support
{
    internal static class SceneHandler
    {
        internal class SceneInitEvent
        {
            internal int buildIndex;
            internal string name;
            internal bool wasLoadedThisTick;
        }

        private static Queue<SceneInitEvent> scenesLoaded = new Queue<SceneInitEvent>();
#if ANDROID
        private static bool sceneNameWarningLogged;
        private static bool sceneIndexWarningLogged;
        private static PropertyInfo sceneBuildIndex = typeof(Scene).GetProperty("buildIndex", BindingFlags.Instance | BindingFlags.Public);
#endif

        internal static bool Init(MethodInfo sceneLoaded, MethodInfo sceneUnloaded)
        {
            bool loaded = false, unloaded = false;
            if (sceneLoaded != null)
                try
                {
                    MethodInfo onSceneLoadPrefix = typeof(SceneHandler).GetMethod("OnSceneLoadPrefix", BindingFlags.Static | BindingFlags.NonPublic);
                    Core.HarmonyInstance.Patch(sceneLoaded, new HarmonyMethod(onSceneLoadPrefix));
                    loaded = true;
                    MelonDebug.Msg($"Hooked into {sceneLoaded.FullDescription()}");
                }
                catch (Exception ex) { MelonLogger.Error($"SceneManager.sceneLoaded override failed: {ex}"); }

            if (sceneUnloaded != null)
                try
                {
                    MethodInfo onSceneUnloadPrefix = typeof(SceneHandler).GetMethod("OnSceneUnloadPrefix", BindingFlags.Static | BindingFlags.NonPublic);
                    Core.HarmonyInstance.Patch(sceneUnloaded, new HarmonyMethod(onSceneUnloadPrefix));
                    unloaded = true;
                    MelonDebug.Msg($"Hooked into {sceneUnloaded.FullDescription()}");
                }
                catch (Exception ex) { MelonLogger.Error($"SceneManager.sceneUnloaded override failed: {ex}"); }
#if ANDROID
            if (sceneLoaded == null)
                MelonLogger.Warning("SceneLoaded callbacks are unavailable: Unity's Internal_SceneLoaded method is missing.");
            if (sceneUnloaded == null)
                MelonLogger.Warning("SceneUnloaded callbacks are unavailable: Unity's Internal_SceneUnloaded method is missing.");
#endif
            return loaded && unloaded;
        }

        private static void OnSceneLoadPrefix(Scene __0, LoadSceneMode __1)
            => OnSceneLoad(__0, __1);
        private static void OnSceneUnloadPrefix(Scene __0)
            => OnSceneUnload(__0);

        private static void OnSceneLoad(Scene scene, LoadSceneMode mode)
        {
#if !ANDROID
            if (Main.obj == null)
                SM_Component.Create();
#endif

            if (ReferenceEquals(scene, null))
                return;

            int buildIndex = GetBuildIndex(scene);
            string sceneName = GetSceneName(scene);
            Main.Interface.OnSceneWasLoaded(buildIndex, sceneName);
            scenesLoaded.Enqueue(new SceneInitEvent { buildIndex = buildIndex, name = sceneName });
        }

        private static void OnSceneUnload(Scene scene)
        {
            if (ReferenceEquals(scene, null))
                return;

            Main.Interface.OnSceneWasUnloaded(GetBuildIndex(scene), GetSceneName(scene));
        }

        private static string GetSceneName(Scene scene)
        {
#if ANDROID
            try
            {
                return scene.name;
            }
            catch (MissingIl2CppInternalCallException)
            {
                if (!sceneNameWarningLogged)
                {
                    sceneNameWarningLogged = true;
                    MelonLogger.Warning(
                        "Scene names are unavailable in this game's stripped Unity runtime; " +
                        "Android scene lifecycle events will use an empty name.");
                }
                return string.Empty;
            }
#else
            return scene.name;
#endif
        }

        private static int GetBuildIndex(Scene scene)
        {
#if ANDROID
            if (sceneBuildIndex != null)
            {
                try { return (int)sceneBuildIndex.GetValue(scene, null); }
                catch (Exception ex) when (IsMissingSceneIndex(ex))
                {
                    sceneBuildIndex = null;
                }
            }
            if (!sceneIndexWarningLogged)
            {
                sceneIndexWarningLogged = true;
                MelonLogger.Warning("Scene build indices are unavailable in this Unity runtime; callbacks will use -1.");
            }
            return -1;
#else
            return scene.buildIndex;
#endif
        }

#if ANDROID
        private static bool IsMissingSceneIndex(Exception exception)
        {
            for (Exception current = exception; current != null; current = current.InnerException)
                if (current is MissingIl2CppInternalCallException || current is MissingMemberException)
                    return true;
            return false;
        }
#endif

        internal static void OnUpdate()
        {
            if (scenesLoaded.Count > 0)
            {
                Queue<SceneInitEvent> requeue = new Queue<SceneInitEvent>();
                SceneInitEvent evt = null;
                while ((scenesLoaded.Count > 0) && ((evt = scenesLoaded.Dequeue()) != null))
                {
                    if (evt.wasLoadedThisTick)
                        Main.Interface.OnSceneWasInitialized(evt.buildIndex, evt.name);
                    else
                    {
                        evt.wasLoadedThisTick = true;
                        requeue.Enqueue(evt);
                    }
                }
                while ((requeue.Count > 0) && ((evt = requeue.Dequeue()) != null))
                    scenesLoaded.Enqueue(evt);
            }
        }
    }
}

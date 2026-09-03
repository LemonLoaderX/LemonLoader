using UnityEngine;

#if SM_Il2Cpp
using System;
using Il2CppInterop.Runtime;
using Il2CppInterop.Runtime.Injection;
#endif

namespace MelonLoader.Support
{
    internal class SM_Component : MonoBehaviour
    {
        private bool isQuitting;

#if SM_Il2Cpp
        public SM_Component(IntPtr value) : base(value) { }
#endif

        internal static void Create()
        {
            if (Main.component != null)
                return;

            MelonCoroutines._hasProcessed = false;

            Main.obj = new GameObject();
            DontDestroyOnLoad(Main.obj);
            Main.obj.hideFlags = HideFlags.DontSave;

#if SM_Il2Cpp
            ClassInjector.RegisterTypeInIl2Cpp<SM_Component>();
            Main.component = Main.obj.AddComponent(Il2CppType.Of<SM_Component>()).TryCast<SM_Component>();
#else
            Main.component = (SM_Component)Main.obj.AddComponent(typeof(SM_Component));
#endif

#if !ANDROID
            ComponentSiblingFix.SetAsLastSibling(Main.obj.transform);
#endif
        }

        private void ProcessCoroutineQueue()
        {
            MelonCoroutines._hasProcessed = true;

            if (MelonCoroutines._queue.Count <= 0)
                return;

            foreach (var queuedCoroutine in MelonCoroutines._queue)
#if SM_Il2Cpp
                StartCoroutine(new Il2CppSystem.Collections.IEnumerator(new MonoEnumeratorWrapper(queuedCoroutine).Pointer));
#else
                StartCoroutine(queuedCoroutine);
#endif

            MelonCoroutines._queue.Clear();
        }

        void Start()
        {
            if ((Main.component == null) || (Main.component != this))
                return;

#if !ANDROID
            ComponentSiblingFix.SetAsLastSibling(transform);
#endif
            Main.Interface.OnApplicationLateStart();
        }

        void Awake()
        {
            ProcessCoroutineQueue();
        }

        void Update()
        {
            if ((Main.component == null) || (Main.component != this))
                return;

            isQuitting = false;
#if !ANDROID
            ComponentSiblingFix.SetAsLastSibling(transform);
#endif
            SceneHandler.OnUpdate();
            Main.Interface.Update();
        }

        void OnDestroy()
        {
            if ((Main.component == null) || (Main.component != this))
                return;

            if (!isQuitting)
            {
                Create();
                return;
            }

            OnApplicationDefiniteQuit();
        }

        void OnApplicationQuit()
        {
            if ((Main.component == null) || (Main.component != this))
                return;

            isQuitting = true;
            Main.Interface.Quit();
        }

        void OnApplicationDefiniteQuit()
        {
            Main.Interface.DefiniteQuit();
        }

        void FixedUpdate()
        {
            if ((Main.component == null) || (Main.component != this))
                return;

            Main.Interface.FixedUpdate();
        }

        void LateUpdate()
        {
            if ((Main.component == null) || (Main.component != this))
                return;

            Main.Interface.LateUpdate();
        }

        void OnGUI()
        {
            if ((Main.component == null) || (Main.component != this))
                return;

            Main.Interface.OnGUI();
        }
    }
}

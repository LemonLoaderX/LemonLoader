using MelonLoader;
using MelonLoader.Android;
using MelonLoader.Utils;
using Java.Interop;

[assembly: MelonInfo(typeof(LemonLoader.Tests.JniHost.DeviceMod), "JNI Migration Probe", "2.0.0", "LemonLoader")]

namespace LemonLoader.Tests.JniHost;

public sealed class DeviceMod : MelonMod
{
    private bool frame;
    public override void OnInitializeMelon()
    {
        try
        {
            Suites.Run("java-interop", 0, 0, LoggerInstance.Msg);
            using var asset = APKAssetManager.GetAssetStream("LemonLoader/payload.json");
            if (asset == null || asset.ReadByte() < 0) throw new Exception("Payload unreadable.");
            asset.Seek(0, SeekOrigin.Begin);
            if (asset.ReadByte() < 0 || APKAssetManager.GetDirectoryContents("LemonLoader").Length == 0)
                throw new Exception("Asset seek/list failed.");
            if (APKAssetManager.GetAssetStream("LemonLoader/absent-new-java-api") != null) throw new Exception("Missing asset accepted.");
            LoggerInstance.Msg("PASS asset read/missing file");
            Task.Run(() =>
            {
                using var thread = AndroidJava.AttachCurrentThread();
                using var activity = UnityPlayer.CurrentActivity ?? throw new Exception("No Activity.");
                using var assets = activity.Assets;
                if (assets.List("LemonLoader").Length == 0) throw new Exception("Worker application ClassLoader failed.");
                LoggerInstance.Msg("PASS application class on CLR worker");
            }).GetAwaiter().GetResult();
            int calls = 0;
            using (var runnable = JavaCallbacks.Create<JavaRunnable>(new JavaCallbackMethod("run", (Action)(() => calls++))))
                runnable.Peer.Run();
            if (calls != 1) throw new Exception("Managed Runnable callback failed.");
            var disposedCallback = JavaCallbacks.Create<JavaRunnable>(new JavaCallbackMethod("run", (Action)(() => throw new Exception("Ended callback ran."))));
            var proxyReference = disposedCallback.Peer.PeerReference;
            using (var retainedProxy = new JavaRunnable(ref proxyReference, JniObjectReferenceOptions.CopyAndDoNotRegister))
            { disposedCallback.Dispose(); retainedProxy.Run(); }
            using (var failing = JavaCallbacks.Create<JavaRunnable>(new JavaCallbackMethod("run", (Action)(() => throw new InvalidOperationException("callback-fixture")))))
            {
                try { failing.Peer.Run(); throw new Exception("Callback failure missing."); }
                catch (JavaException e)
                {
                    if (!e.Message.Contains("callback-fixture") || !e.Message.Contains(nameof(OnInitializeMelon))) throw;
                    e.Dispose();
                }
            }
            using (var comparator = JavaCallbacks.Create<JavaComparator>(new JavaCallbackMethod("compare", (Func<JavaObject, JavaObject, int>)((a, b) => 7))))
            {
                var compare = JavaBinding.BindInstance<Func<JavaComparator, JavaObject, JavaObject, int>>("java/util/Comparator", "compare");
                if (compare(comparator.Peer, null!, null!) != 7) throw new Exception("Callback primitive boxing failed.");
            }
            try
            {
                using var invalid = JavaCallbacks.Create<JavaComparator>(new JavaCallbackMethod("wrong", (Action)(() => { })));
                throw new Exception("Missing interface method accepted.");
            }
            catch (JavaException e) { e.Dispose(); }
            LoggerInstance.Msg("PASS callbacks/exception containment");
            _ = CheckUiThread();
        }
        catch (Exception e) { LoggerInstance.Error("FAIL JNI migration: " + e); }
    }
    private async Task CheckUiThread()
    {
        try
        {
            await Task.Run(async () =>
            {
                await AndroidThread.RunAsync(() =>
                {
                    var current = JavaBinding.BindStatic<Func<JavaLooper>>("android/os/Looper", "myLooper");
                    var main = JavaBinding.BindStatic<Func<JavaLooper>>("android/os/Looper", "getMainLooper");
                    using var actual = current();
                    using var expected = main();
                    if (!actual.Equals(expected)) throw new Exception("Callback did not run on Android UI thread.");
                }).WaitAsync(TimeSpan.FromSeconds(15));
                try { await AndroidThread.RunAsync(() => throw new InvalidOperationException("ui-fixture")); throw new Exception("UI exception missing."); }
                catch (InvalidOperationException e) when (e.Message == "ui-fixture") { }
            });
            LoggerInstance.Msg("PASS UI thread/task exception");
        }
        catch (Exception e) { LoggerInstance.Error("FAIL JNI UI dispatch: " + e); }
    }
    public override void OnUpdate()
    {
        if (frame) return;
        frame = true;
        LoggerInstance.Msg("FRAME after migration");
    }
}

[JniTypeSignature("java/util/Comparator", GenerateJavaPeer = false)]
public sealed class JavaComparator : JavaObject
{
    public JavaComparator(ref JniObjectReference reference, JniObjectReferenceOptions options) : base(ref reference, options) { }
}
[JniTypeSignature("android/os/Looper", GenerateJavaPeer = false)]
public sealed class JavaLooper : JavaObject
{
    public JavaLooper(ref JniObjectReference reference, JniObjectReferenceOptions options) : base(ref reference, options) { }
}

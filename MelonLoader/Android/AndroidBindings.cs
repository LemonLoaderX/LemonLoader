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

[JniTypeSignature("android/app/Activity", GenerateJavaPeer = false)]
public sealed class AndroidActivity : AndroidContext
{
    private static readonly JniPeerMembers members = new("android/app/Activity", typeof(AndroidActivity));
    private static readonly Action<AndroidActivity, JavaRunnable> runOnUiThread =
        JavaBinding.BindInstance<Action<AndroidActivity, JavaRunnable>>("android/app/Activity", "runOnUiThread");
    public override JniPeerMembers JniPeerMembers => members;
    public AndroidActivity(ref JniObjectReference reference, JniObjectReferenceOptions options) : base(ref reference, options) { }
    public void RunOnUiThread(JavaRunnable action) => runOnUiThread(this, action);
}

[JniTypeSignature("android/content/Context", GenerateJavaPeer = false)]
public class AndroidContext : JavaObject
{
    private static readonly JniPeerMembers members = new("android/content/Context", typeof(AndroidContext));
    private static readonly Func<AndroidContext, AndroidAssetManager> assets =
        JavaBinding.BindInstance<Func<AndroidContext, AndroidAssetManager>>("android/content/Context", "getAssets");
    private static readonly Func<AndroidContext, string> packageName =
        JavaBinding.BindInstance<Func<AndroidContext, string>>("android/content/Context", "getPackageName");
    public override JniPeerMembers JniPeerMembers => members;
    public AndroidContext(ref JniObjectReference reference, JniObjectReferenceOptions options) : base(ref reference, options) { }
    public AndroidAssetManager Assets => assets(this);
    public string PackageName => packageName(this);
}

[JniTypeSignature("android/content/res/AssetManager", GenerateJavaPeer = false)]
public sealed class AndroidAssetManager : JavaObject
{
    private static readonly JniPeerMembers members = new("android/content/res/AssetManager", typeof(AndroidAssetManager));
    private static readonly Func<AndroidAssetManager, string, JavaInputStream> open =
        JavaBinding.BindInstance<Func<AndroidAssetManager, string, JavaInputStream>>("android/content/res/AssetManager", "open");
    private static readonly Func<AndroidAssetManager, string, string[]> list =
        JavaBinding.BindInstance<Func<AndroidAssetManager, string, string[]>>("android/content/res/AssetManager", "list");
    public override JniPeerMembers JniPeerMembers => members;
    public AndroidAssetManager(ref JniObjectReference reference, JniObjectReferenceOptions options) : base(ref reference, options) { }
    public JavaInputStream Open(string path) => open(this, path);
    public string[] List(string directory) => list(this, directory);
}

#endif

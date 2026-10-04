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
    public override JniPeerMembers JniPeerMembers => members;
    public AndroidActivity(ref JniObjectReference reference, JniObjectReferenceOptions options) : base(ref reference, options) { }
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

[JniTypeSignature("java/io/InputStream", GenerateJavaPeer = false)]
public sealed class JavaInputStream : JavaObject
{
    private static readonly JniPeerMembers members = new("java/io/InputStream", typeof(JavaInputStream));
    private static readonly Func<JavaInputStream, int> available = JavaBinding.BindInstance<Func<JavaInputStream, int>>("java/io/InputStream", "available");
    private static readonly Func<JavaInputStream, bool> markSupported = JavaBinding.BindInstance<Func<JavaInputStream, bool>>("java/io/InputStream", "markSupported");
    private static readonly Action<JavaInputStream, int> mark = JavaBinding.BindInstance<Action<JavaInputStream, int>>("java/io/InputStream", "mark");
    private static readonly Func<JavaInputStream, long, long> skip = JavaBinding.BindInstance<Func<JavaInputStream, long, long>>("java/io/InputStream", "skip");
    private static readonly Action<JavaInputStream> reset = JavaBinding.BindInstance<Action<JavaInputStream>>("java/io/InputStream", "reset");
    private static readonly Action<JavaInputStream> close = JavaBinding.BindInstance<Action<JavaInputStream>>("java/io/InputStream", "close");
    private static readonly Func<JavaInputStream, JavaSByteArray, int, int, int> read =
        JavaBinding.BindInstance<Func<JavaInputStream, JavaSByteArray, int, int, int>>("java/io/InputStream", "read");
    public override JniPeerMembers JniPeerMembers => members;
    public JavaInputStream(ref JniObjectReference reference, JniObjectReferenceOptions options) : base(ref reference, options) { }
    public int Available => available(this);
    public bool MarkSupported => markSupported(this);
    public void Mark(int limit) => mark(this, limit);
    public long Skip(long count) => skip(this, count);
    public void Reset() => reset(this);
    public void Close() => close(this);
    public int Read(JavaSByteArray buffer, int offset, int count) => read(this, buffer, offset, count);
}
#endif

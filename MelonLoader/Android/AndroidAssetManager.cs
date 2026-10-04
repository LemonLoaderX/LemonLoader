#if ANDROID
#nullable enable
using System;
using Java.Interop;

namespace MelonLoader.Android;

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

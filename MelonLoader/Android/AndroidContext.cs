#if ANDROID
#nullable enable
using System;
using Java.Interop;

namespace MelonLoader.Android;

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
#endif

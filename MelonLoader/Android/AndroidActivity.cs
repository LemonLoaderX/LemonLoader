#if ANDROID
#nullable enable
using System;
using Java.Interop;

namespace MelonLoader.Android;

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
#endif

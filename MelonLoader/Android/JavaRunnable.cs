#if ANDROID
#nullable enable
using System;
using Java.Interop;

namespace MelonLoader.Android;

[JniTypeSignature("java/lang/Runnable", GenerateJavaPeer = false)]
public sealed class JavaRunnable : JavaObject
{
    private static readonly JniPeerMembers members = new("java/lang/Runnable", typeof(JavaRunnable), isInterface: true);
    private static readonly Action<JavaRunnable> run = JavaBinding.BindInstance<Action<JavaRunnable>>("java/lang/Runnable", "run");
    public override JniPeerMembers JniPeerMembers => members;
    public JavaRunnable(ref JniObjectReference reference, JniObjectReferenceOptions options) : base(ref reference, options) { }
    public void Run() => run(this);
}

#endif

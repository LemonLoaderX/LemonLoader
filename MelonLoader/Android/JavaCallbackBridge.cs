#if ANDROID
#nullable enable
using System;
using System.IO;
using System.Runtime.InteropServices;
using Java.Interop;

namespace MelonLoader.Android;

internal sealed unsafe record JavaCallbackBridge(JniType Type, JniMethodInfo Constructor, JniMethodInfo Proxy,
    JavaClassLoader Loader, JavaByteBuffer Buffer)
{
    internal static JavaCallbackBridge Load(Delegate dispatch)
    {
        using var thread = AndroidJava.AttachCurrentThread();
        var host = AndroidJava.Host;
        if (host.ApplicationClassLoader == 0) throw new InvalidOperationException("Android callbacks require the application's ClassLoader.");
        using var resource = typeof(JavaCallbackBridge).Assembly.GetManifestResourceStream("MelonLoader.Android.Callbacks.dex")
            ?? throw new FileNotFoundException("Embedded Android callback support is missing.");
        using var memory = new MemoryStream();
        resource.CopyTo(memory);
        var data = memory.ToArray();
        var signed = MemoryMarshal.Cast<byte, sbyte>(data).ToArray();
        var wrap = JavaBinding.BindStatic<Func<sbyte[], JavaByteBuffer>>("java/nio/ByteBuffer", "wrap");
        var buffer = wrap(signed);
        var original = new JniObjectReference(host.ApplicationClassLoader, JniObjectReferenceType.Global);
        JavaClassLoader? loader = null;
        try
        {
            using var parent = new JavaClassLoader(ref original, JniObjectReferenceOptions.CopyAndDoNotRegister);
            var create = JavaBinding.BindConstructor<Func<JavaByteBuffer, JavaClassLoader, JavaClassLoader>>("dalvik/system/InMemoryDexClassLoader");
            loader = create(buffer, parent);
            using var klass = loader.LoadClass("org.lemonloader.interop.NativeCallback");
            var reference = klass.PeerReference;
            var type = new JniType(ref reference, JniObjectReferenceOptions.Copy);
            try
            {
                type.RegisterNativeMethods(new JniNativeMethodRegistration("invoke", "(JLjava/lang/String;[Ljava/lang/Object;)Ljava/lang/Object;", dispatch));
                return new JavaCallbackBridge(type, type.GetInstanceMethod("<init>", "(J)V"),
                    type.GetInstanceMethod("proxy", "(Ljava/lang/String;[Ljava/lang/String;)Ljava/lang/Object;"), loader, buffer);
            }
            catch { type.Dispose(); throw; }
        }
        catch { loader?.Dispose(); buffer.Dispose(); throw; }
    }
}

[JniTypeSignature("java/nio/ByteBuffer", GenerateJavaPeer = false)]
internal sealed class JavaByteBuffer : JavaObject
{
    public JavaByteBuffer(ref JniObjectReference reference, JniObjectReferenceOptions options) : base(ref reference, options) { }
}

[JniTypeSignature("java/lang/ClassLoader", GenerateJavaPeer = false)]
internal sealed class JavaClassLoader : JavaObject
{
    private static readonly Func<JavaClassLoader, string, JavaClass> load = JavaBinding.BindInstance<Func<JavaClassLoader, string, JavaClass>>("java/lang/ClassLoader", "loadClass");
    public JavaClassLoader(ref JniObjectReference reference, JniObjectReferenceOptions options) : base(ref reference, options) { }
    internal JavaClass LoadClass(string name) => load(this, name);
}

[JniTypeSignature("java/lang/Class", GenerateJavaPeer = false)]
internal sealed class JavaClass : JavaObject
{
    public JavaClass(ref JniObjectReference reference, JniObjectReferenceOptions options) : base(ref reference, options) { }
}

#endif

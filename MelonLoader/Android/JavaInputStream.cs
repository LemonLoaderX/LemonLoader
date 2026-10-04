#if ANDROID
#nullable enable
using System;
using Java.Interop;

namespace MelonLoader.Android;

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

#if ANDROID
#nullable enable
using System;
using Java.Interop;

namespace MelonLoader.Java;

public readonly struct JMethodID : IEquatable<JMethodID>
{
    internal readonly JniMethodInfo? Info;
    internal readonly string? Signature;
    internal readonly string? Name;
    public IntPtr Handle => Info?.ID ?? IntPtr.Zero;
    internal JMethodID(JniMethodInfo info, string? signature = null, string? name = null) { Info = info; Signature = signature; Name = name; }
    public static implicit operator IntPtr(JMethodID id) => id.Handle;
    [Obsolete("Resolve IDs through JClass to retain invocation kind and signature.")]
    public static implicit operator JMethodID(IntPtr handle) => new(new JniMethodInfo(handle, false));
    internal JniMethodInfo Require(bool isStatic)
    {
        if (Info == null || Handle == IntPtr.Zero) throw new ArgumentException("Method ID is invalid.");
        if (Info.IsStatic != isStatic) throw new ArgumentException("Method ID invocation kind does not match.");
        return Info;
    }
    public bool Equals(JMethodID other) => Handle == other.Handle;
    public override bool Equals(object? value) => value is JMethodID other && Equals(other);
    public override int GetHashCode() => Handle.GetHashCode();
}
#endif

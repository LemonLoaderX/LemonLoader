#if ANDROID
#nullable enable
using System;
using Java.Interop;

namespace MelonLoader.Java;

public readonly struct JFieldID : IEquatable<JFieldID>
{
    internal readonly JniFieldInfo? Info;
    internal readonly string? Signature;
    public IntPtr Handle => Info?.ID ?? IntPtr.Zero;
    internal JFieldID(JniFieldInfo info, string? signature = null) { Info = info; Signature = signature; }
    public static implicit operator IntPtr(JFieldID id) => id.Handle;
    [Obsolete("Resolve IDs through JClass to retain field kind.")]
    public static implicit operator JFieldID(IntPtr handle) => new(new JniFieldInfo(handle, false));
    internal JniFieldInfo Require(bool isStatic)
    {
        if (Info == null || Handle == IntPtr.Zero) throw new ArgumentException("Field ID is invalid.");
        if (Info.IsStatic != isStatic) throw new ArgumentException("Field ID access kind does not match.");
        return Info;
    }
    public bool Equals(JFieldID other) => Handle == other.Handle;
    public override bool Equals(object? value) => value is JFieldID other && Equals(other);
    public override int GetHashCode() => Handle.GetHashCode();
}
#endif

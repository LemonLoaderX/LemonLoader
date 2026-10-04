#if ANDROID
#nullable enable
using System;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using Java.Interop;

namespace MelonLoader.Java;

public static unsafe partial class JNI
{
    public static JArray<T> NewArray<T>(int length)
    {
        EnsureThread();
        if (length < 0) throw new ArgumentOutOfRangeException(nameof(length));
        if (typeof(T) == typeof(bool)) return Global<JArray<T>>(JniEnvironment.Arrays.NewBooleanArray(length));
        if (typeof(T) == typeof(sbyte)) return Global<JArray<T>>(JniEnvironment.Arrays.NewByteArray(length));
        if (typeof(T) == typeof(char)) return Global<JArray<T>>(JniEnvironment.Arrays.NewCharArray(length));
        if (typeof(T) == typeof(short)) return Global<JArray<T>>(JniEnvironment.Arrays.NewShortArray(length));
        if (typeof(T) == typeof(int)) return Global<JArray<T>>(JniEnvironment.Arrays.NewIntArray(length));
        if (typeof(T) == typeof(long)) return Global<JArray<T>>(JniEnvironment.Arrays.NewLongArray(length));
        if (typeof(T) == typeof(float)) return Global<JArray<T>>(JniEnvironment.Arrays.NewFloatArray(length));
        if (typeof(T) == typeof(double)) return Global<JArray<T>>(JniEnvironment.Arrays.NewDoubleArray(length));
        throw new ArgumentException("Unsupported Java array element type.");
    }

    public static void SetArrayRegion<T>(JArray<T> value, int start, ReadOnlySpan<T> source)
    {
        _ = GetTypeSignature<T>();
        var reference = Ref(value);
        if (start < 0 || start > GetArrayLength(value) - source.Length) throw new ArgumentOutOfRangeException(nameof(start));
        if (source.IsEmpty) return;
        fixed (byte* buffer = &Unsafe.As<T, byte>(ref MemoryMarshal.GetReference(source)))
        {
            if (typeof(T) == typeof(bool)) { JniEnvironment.Arrays.SetBooleanArrayRegion(reference, start, source.Length, (bool*)buffer); return; }
            if (typeof(T) == typeof(sbyte)) { JniEnvironment.Arrays.SetByteArrayRegion(reference, start, source.Length, (sbyte*)buffer); return; }
            if (typeof(T) == typeof(char)) { JniEnvironment.Arrays.SetCharArrayRegion(reference, start, source.Length, (char*)buffer); return; }
            if (typeof(T) == typeof(short)) { JniEnvironment.Arrays.SetShortArrayRegion(reference, start, source.Length, (short*)buffer); return; }
            if (typeof(T) == typeof(int)) { JniEnvironment.Arrays.SetIntArrayRegion(reference, start, source.Length, (int*)buffer); return; }
            if (typeof(T) == typeof(long)) { JniEnvironment.Arrays.SetLongArrayRegion(reference, start, source.Length, (long*)buffer); return; }
            if (typeof(T) == typeof(float)) { JniEnvironment.Arrays.SetFloatArrayRegion(reference, start, source.Length, (float*)buffer); return; }
            if (typeof(T) == typeof(double)) { JniEnvironment.Arrays.SetDoubleArrayRegion(reference, start, source.Length, (double*)buffer); return; }
        }
    }

    public static void GetArrayRegion<T>(JArray<T> value, int start, Span<T> destination)
    {
        _ = GetTypeSignature<T>();
        var reference = Ref(value);
        if (start < 0 || start > GetArrayLength(value) - destination.Length) throw new ArgumentOutOfRangeException(nameof(start));
        if (destination.IsEmpty) return;
        fixed (byte* buffer = &Unsafe.As<T, byte>(ref MemoryMarshal.GetReference(destination)))
        {
            if (typeof(T) == typeof(bool)) { JniEnvironment.Arrays.GetBooleanArrayRegion(reference, start, destination.Length, (bool*)buffer); return; }
            if (typeof(T) == typeof(sbyte)) { JniEnvironment.Arrays.GetByteArrayRegion(reference, start, destination.Length, (sbyte*)buffer); return; }
            if (typeof(T) == typeof(char)) { JniEnvironment.Arrays.GetCharArrayRegion(reference, start, destination.Length, (char*)buffer); return; }
            if (typeof(T) == typeof(short)) { JniEnvironment.Arrays.GetShortArrayRegion(reference, start, destination.Length, (short*)buffer); return; }
            if (typeof(T) == typeof(int)) { JniEnvironment.Arrays.GetIntArrayRegion(reference, start, destination.Length, (int*)buffer); return; }
            if (typeof(T) == typeof(long)) { JniEnvironment.Arrays.GetLongArrayRegion(reference, start, destination.Length, (long*)buffer); return; }
            if (typeof(T) == typeof(float)) { JniEnvironment.Arrays.GetFloatArrayRegion(reference, start, destination.Length, (float*)buffer); return; }
            if (typeof(T) == typeof(double)) { JniEnvironment.Arrays.GetDoubleArrayRegion(reference, start, destination.Length, (double*)buffer); return; }
        }
    }
}
#endif

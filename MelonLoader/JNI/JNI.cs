#if ANDROID
#nullable enable
using System;
using System.Runtime.InteropServices;
using Java.Interop;

namespace MelonLoader.Java;

/// <summary>Checked JNI operations. Object results own global references unless marked Local.</summary>
public static unsafe partial class JNI
{
    internal static JniObjectReference Ref(JObject? value)
    {
        var reference = value?.Reference ?? default;
        if (value?.ReferenceType == ReferenceType.WeakGlobal)
            throw new InvalidOperationException("Promote weak globals with ToLocal or ToGlobal before use.");
        EnsureThread();
        return reference;
    }

    internal static T Wrap<T>(JniObjectReference reference) where T : JObject, new()
    {
        T value = new();
        value.SetReference(reference, true);
        return value;
    }

    private static T Global<T>(JniObjectReference local) where T : JObject, new()
    {
        CheckExceptionAndThrow();
        if (!local.IsValid) return Wrap<T>(default);
        try { return Wrap<T>(CopyGlobal(local)); }
        finally { JniObjectReference.Dispose(ref local); }
    }

    private static JniObjectReference CopyGlobal(JniObjectReference value)
    {
        CheckExceptionAndThrow();
        var result = value.NewGlobalRef();
        CheckExceptionAndThrow();
        return result;
    }

    /// <summary>Borrow a native reference. Disposing the wrapper never deletes that reference.</summary>
    public static T Borrow<T>(IntPtr handle, ReferenceType type) where T : JObject, new()
    {
        EnsureThread();
        T value = new();
        value.SetReference(new JniObjectReference(handle, ToInteropType(type)), false);
        return value;
    }

    /// <summary>Take ownership of a native reference. The caller must not delete or reuse it.</summary>
    public static T Adopt<T>(IntPtr handle, ReferenceType type) where T : JObject, new()
    {
        EnsureThread();
        var reference = new JniObjectReference(handle, ToInteropType(type));
        if (reference.Type == JniObjectReferenceType.Local) JniEnvironment.References.CreatedReference(reference);
        return Wrap<T>(reference);
    }

    public static T NewGlobalRef<T>(JObject value) where T : JObject, new()
    { var source = value.Reference; EnsureThread(); return CopyClassCache(value, Wrap<T>(CopyGlobal(source))); }
    public static T NewLocalRef<T>(JObject value) where T : JObject, new()
    {
        var source = value.Reference;
        EnsureThread(); CheckExceptionAndThrow();
        var result = source.NewLocalRef();
        CheckExceptionAndThrow();
        return CopyClassCache(value, Wrap<T>(result));
    }
    private static T CopyClassCache<T>(JObject source, T result) where T : JObject
    {
        if (source is JClass sourceClass && result is JClass resultClass) resultClass.Cache = sourceClass.Cache;
        return result;
    }
    public static T NewWeakGlobalRef<T>(JObject value) where T : JObject, new()
    {
        var source = Ref(value); CheckExceptionAndThrow();
        var result = source.NewWeakGlobalRef(); CheckExceptionAndThrow();
        return Wrap<T>(result);
    }

    public static void DeleteGlobalRef(JObject value) => DeleteReference(value, ReferenceType.Global);
    public static void DeleteLocalRef(JObject value) => DeleteReference(value, ReferenceType.Local);
    public static void DeleteWeakGlobalRef(JObject value) => DeleteReference(value, ReferenceType.WeakGlobal);
    private static void DeleteReference(JObject value, ReferenceType type)
    {
        if (value == null || value.IsDisposed) return;
        if (!value.IsNull && value.ReferenceType != type) throw new ArgumentException("Reference kind does not match.");
        value.Dispose();
    }

    public static JClass FindClass(string name)
    {
        EnsureThread();
        if (string.IsNullOrWhiteSpace(name)) throw new ArgumentException("Class name is required.", nameof(name));
        name = name.Replace('.', '/');
        lock (classes)
        {
            if (!classes.TryGetValue(name, out var cached))
            {
                JniObjectReference local;
                if (runtime!.ApplicationClassLoader.IsValid)
                {
                    using var type = new JniType("java/lang/Class");
                    var javaName = JniEnvironment.Strings.NewString(name.Replace('/', '.'));
                    try
                    {
                        JniArgumentValue* args = stackalloc JniArgumentValue[3]
                        {
                            new(javaName), new(false), new(runtime.ApplicationClassLoader)
                        };
                        local = JniEnvironment.StaticMethods.CallStaticObjectMethod(type.PeerReference,
                            type.GetStaticMethod("forName", "(Ljava/lang/String;ZLjava/lang/ClassLoader;)Ljava/lang/Class;"), args);
                    }
                    finally { JniObjectReference.Dispose(ref javaName); }
                }
                else local = JniEnvironment.Types.FindClass(name);
                cached = Global<JClass>(local);
                classes.Add(name, cached);
            }
            var result = NewLocalRef<JClass>(cached);
            result.Cache = cached.Cache;
            return result;
        }
    }

    public static JClass GetObjectClass(JObject value) => Global<JClass>(JniEnvironment.Types.GetObjectClass(Ref(value)));
    public static JClass GetSuperClass(JClass value) => Global<JClass>(JniEnvironment.Types.GetSuperclass(Ref(value)));
    public static bool IsSameObject(JObject? first, JObject? second) => JniEnvironment.Types.IsSameObject(Ref(first), Ref(second));
    public static bool IsInstanceOf(JObject value, JClass type) => JniEnvironment.Types.IsInstanceOf(Ref(value), Ref(type));
    public static bool IsAssignableFrom(JClass sub, JClass sup) => JniEnvironment.Types.IsAssignableFrom(Ref(sub), Ref(sup));

    internal static JMethodID ResolveMethod(JClass type, string name, string signature, bool isStatic)
    {
        ValidateSignature(signature, true);
        var reference = Ref(type);
        var info = isStatic ? JniEnvironment.StaticMethods.GetStaticMethodID(reference, name, signature) :
            JniEnvironment.InstanceMethods.GetMethodID(reference, name, signature);
        return new JMethodID(info, signature, name);
    }
    internal static JFieldID ResolveField(JClass type, string name, string signature, bool isStatic)
    {
        ValidateSignature(signature, false);
        return new(isStatic ? JniEnvironment.StaticFields.GetStaticFieldID(Ref(type), name, signature) :
            JniEnvironment.InstanceFields.GetFieldID(Ref(type), name, signature), signature);
    }

    private static void ValidateSignature(string signature, bool method)
    {
        if (string.IsNullOrEmpty(signature)) throw new ArgumentException("JNI signature is required.");
        int position = 0;
        if (method)
        {
            if (signature[position++] != '(') throw new ArgumentException("Method signature must start with '('.");
            while (position < signature.Length && signature[position] != ')') ParseType(signature, ref position, false);
            if (position >= signature.Length || signature[position++] != ')') throw new ArgumentException("Unterminated method signature.");
        }
        ParseType(signature, ref position, method);
        if (position != signature.Length) throw new ArgumentException("Unexpected trailing JNI signature data.");
    }

    private static void ParseType(string signature, ref int position, bool allowVoid)
    {
        bool array = false;
        while (position < signature.Length && signature[position] == '[') { position++; array = true; }
        if (position >= signature.Length) throw new ArgumentException("Incomplete JNI type.");
        char type = signature[position++];
        if (type == 'L')
        {
            int end = signature.IndexOf(';', position);
            if (end <= position || signature.Substring(position, end - position).IndexOf('.') >= 0)
                throw new ArgumentException("Use slash-separated JNI object signatures.");
            position = end + 1;
        }
        else if ("ZBCSIJFD".IndexOf(type) < 0 && !(type == 'V' && allowVoid && !array))
            throw new ArgumentException("Invalid JNI type.");
    }

    private static void ValidateField(JFieldID field, string result)
    {
        if (field.Signature == null) return;
        if (result == "object" ? field.Signature[0] != 'L' && field.Signature[0] != '[' : field.Signature != result)
            throw new ArgumentException("Field type does not match JNI signature.");
    }
    public static JMethodID GetMethodID(JClass type, string name, string signature) => type.GetMethodID(name, signature);
    public static JMethodID GetStaticMethodID(JClass type, string name, string signature) => type.GetStaticMethodID(name, signature);
    public static JFieldID GetFieldID(JClass type, string name, string signature) => type.GetFieldID(name, signature);
    public static JFieldID GetStaticFieldID(JClass type, string name, string signature) => type.GetStaticFieldID(name, signature);

    private static void ValidateCall(JMethodID method, int count, string result)
    {
        if (method.Signature == null) return;
        string signature = method.Signature;
        int parameters = 0, i = 1;
        while (i < signature.Length && signature[i] != ')')
        {
            while (signature[i] == '[') i++;
            if (signature[i] == 'L') { i = signature.IndexOf(';', i); if (i < 0) throw new ArgumentException("Invalid JNI signature."); }
            i++; parameters++;
        }
        if (i >= signature.Length - 1 || count != parameters) throw new ArgumentException("Argument count does not match JNI signature.");
        char returned = signature[i + 1];
        if (result == "object" ? returned != 'L' && returned != '[' : !signature.AsSpan(i + 1).SequenceEqual(result.AsSpan()))
            throw new ArgumentException("Return type does not match JNI signature.");
    }

    public static JString NewString(string value) { EnsureThread(); return Global<JString>(JniEnvironment.Strings.NewString(value)); }
    public static JString NewStringLocal(string value) { EnsureThread(); return Wrap<JString>(JniEnvironment.Strings.NewString(value)); }
    public static string GetJStringString(JString value) => JniEnvironment.Strings.ToString(Ref(value)) ?? "";
    public static int GetStringLength(JString value) => JniEnvironment.Strings.GetStringLength(Ref(value));
    public static string GetStringRegion(JString value, int start, int length)
    {
        if (start < 0 || length < 0 || start > GetStringLength(value) - length) throw new ArgumentOutOfRangeException(nameof(start));
        return GetJStringString(value).Substring(start, length);
    }

    public static T AllocObject<T>(JClass type) where T : JObject, new() => Global<T>(JniEnvironment.Object.AllocObject(Ref(type)));
    public static T NewObject<T>(JClass type, JMethodID constructor, params JValue[] args) where T : JObject, new() =>
        NewObject<T>(type, constructor, (ReadOnlySpan<JValue>)args);
    public static T NewObject<T>(JClass type, JMethodID constructor, ReadOnlySpan<JValue> args) where T : JObject, new()
    {
        var reference = Ref(type);
        if (constructor.Name != null && constructor.Name != "<init>") throw new ArgumentException("NewObject requires a constructor ID.");
        ValidateCall(constructor, args.Length, "V");
        fixed (JValue* values = args) return Global<T>(JniEnvironment.Object.NewObject(reference, constructor.Require(false), (JniArgumentValue*)values));
    }

    public static T NewObjectLocal<T>(JClass type, JMethodID constructor, ReadOnlySpan<JValue> args) where T : JObject, new()
    {
        var reference = Ref(type);
        if (constructor.Name != null && constructor.Name != "<init>") throw new ArgumentException("NewObject requires a constructor ID.");
        ValidateCall(constructor, args.Length, "V");
        fixed (JValue* values = args) return Wrap<T>(JniEnvironment.Object.NewObject(reference, constructor.Require(false), (JniArgumentValue*)values));
    }

    public static T CallObjectMethodLocal<T>(JObject value, JMethodID method, ReadOnlySpan<JValue> args) where T : JObject, new()
    {
        var reference = Ref(value);
        ValidateCall(method, args.Length, "object");
        fixed (JValue* values = args) return Wrap<T>(JniEnvironment.InstanceMethods.CallObjectMethod(reference, method.Require(false), (JniArgumentValue*)values));
    }

    public static T CallStaticObjectMethodLocal<T>(JClass type, JMethodID method, ReadOnlySpan<JValue> args) where T : JObject, new()
    {
        var reference = Ref(type);
        ValidateCall(method, args.Length, "object");
        fixed (JValue* values = args) return Wrap<T>(JniEnvironment.StaticMethods.CallStaticObjectMethod(reference, method.Require(true), (JniArgumentValue*)values));
    }

    public static JObjectArray<T> NewObjectArray<T>(int length, JClass elementClass, T? initial = null) where T : JObject, new()
    {
        if (length < 0) throw new ArgumentOutOfRangeException(nameof(length));
        return Global<JObjectArray<T>>(JniEnvironment.Arrays.NewObjectArray(length, Ref(elementClass), Ref(initial)));
    }

    public static T GetObjectField<T>(JObject value, JFieldID field) where T : JObject, new() =>
        ReadObjectField<T>(value, field, false);
    public static T GetStaticObjectField<T>(JClass type, JFieldID field) where T : JObject, new() =>
        ReadObjectField<T>(type, field, true);
    private static T ReadObjectField<T>(JObject value, JFieldID field, bool isStatic) where T : JObject, new()
    {
        ValidateField(field, "object");
        return Global<T>(isStatic ? JniEnvironment.StaticFields.GetStaticObjectField(Ref(value), field.Require(true)) :
            JniEnvironment.InstanceFields.GetObjectField(Ref(value), field.Require(false)));
    }
    public static void SetObjectField(JObject value, JFieldID field, JObject? data)
    { ValidateField(field, "object"); JniEnvironment.InstanceFields.SetObjectField(Ref(value), field.Require(false), Ref(data)); }
    public static void SetStaticObjectField<T>(JClass type, JFieldID field, T? data) where T : JObject, new()
    { ValidateField(field, "object"); JniEnvironment.StaticFields.SetStaticObjectField(Ref(type), field.Require(true), Ref(data)); }

    public static int GetArrayLength<T>(JArray<T> value) => JniEnvironment.Arrays.GetArrayLength(Ref(value));
    public static int GetArrayLength<T>(JObjectArray<T> value) where T : JObject, new() => JniEnvironment.Arrays.GetArrayLength(Ref(value));
    public static T GetObjectArrayElement<T>(JObjectArray<T> value, int index) where T : JObject, new() =>
        Global<T>(JniEnvironment.Arrays.GetObjectArrayElement(Ref(value), index));
    public static void SetObjectArrayElement<T>(JObjectArray<T> value, int index, T? element) where T : JObject, new() =>
        JniEnvironment.Arrays.SetObjectArrayElement(Ref(value), index, Ref(element));
    public static T[] GetArrayElements<T>(JArray<T> value) => GetArrayRegion(value, 0, value.Length);
    public static T[] GetArrayRegion<T>(JArray<T> value, int start, int length)
    {
        if (length < 0) throw new ArgumentOutOfRangeException(nameof(length));
        var result = new T[length];
        GetArrayRegion(value, start, result.AsSpan());
        return result;
    }
    public static void SetArrayRegion<T>(JArray<T> value, int start, int length, T[] source)
    {
        if (source == null) throw new ArgumentNullException(nameof(source));
        if (length < 0 || length > source.Length) throw new ArgumentOutOfRangeException(nameof(length));
        SetArrayRegion(value, start, (ReadOnlySpan<T>)source.AsSpan(0, length));
    }
    public static T GetArrayElement<T>(JArray<T> value, int index) => GetArrayRegion(value, index, 1)[0];
    public static void SetArrayElement<T>(JArray<T> value, int index, T data) => SetArrayRegion(value, index, (ReadOnlySpan<T>)new T[] { data });
    internal static void CopyByteArrayRegion(JArray<sbyte> value, byte[] buffer, int offset, int count)
    {
        if (buffer == null) throw new ArgumentNullException(nameof(buffer));
        if (offset < 0 || count < 0 || offset > buffer.Length - count) throw new ArgumentOutOfRangeException(nameof(offset));
        GetArrayRegion(value, 0, MemoryMarshal.Cast<byte, sbyte>(buffer.AsSpan(offset, count)));
    }

    public static JThrowable ExceptionOccurred()
    {
        EnsureThread();
        return Wrap<JThrowable>(JniEnvironment.Exceptions.ExceptionOccurred());
    }
    public static void Throw(JThrowable throwable) => JniEnvironment.Exceptions.Throw(Ref(throwable));
    public static void ThrowNew(JClass type, string message) => JniEnvironment.Exceptions.ThrowNew(Ref(type), message);
    public static int EnsureLocalCapacity(int capacity) { EnsureThread(); JniEnvironment.References.EnsureLocalCapacity(capacity); return 0; }
    public static int MonitorEnter(JObject value) { JniEnvironment.Monitors.MonitorEnter(Ref(value)); return 0; }
    public static int MonitorExit(JObject value) { JniEnvironment.Monitors.MonitorExit(Ref(value)); return 0; }
}
#endif

#if ANDROID
#nullable enable
using System;
using Java.Interop;

namespace MelonLoader.Java;

public static unsafe partial class JNI
{
    public static T CallObjectMethod<T>(JObject value, JMethodID method, params JValue[] args) where T : JObject, new() =>
        CallObjectMethod<T>(value, method, (ReadOnlySpan<JValue>)args);
    public static T CallObjectMethod<T>(JObject value, JMethodID method, ReadOnlySpan<JValue> args) where T : JObject, new()
    {
        var info = method.Require(false);
        ValidateCall(method, args.Length, "object");
        fixed (JValue* values = args)
        {
            return Global<T>(JniEnvironment.InstanceMethods.CallObjectMethod(Ref(value), info, (JniArgumentValue*)values));
        }
    }

    public static void CallVoidMethod(JObject value, JMethodID method, params JValue[] args) =>
        CallVoidMethod(value, method, (ReadOnlySpan<JValue>)args);
    public static void CallVoidMethod(JObject value, JMethodID method, ReadOnlySpan<JValue> args)
    {
        var info = method.Require(false);
        ValidateCall(method, args.Length, "V");
        fixed (JValue* values = args)
        {
            JniEnvironment.InstanceMethods.CallVoidMethod(Ref(value), info, (JniArgumentValue*)values);
        }
    }

    public static T CallMethod<T>(JObject value, JMethodID method, params JValue[] args) =>
        CallMethod<T>(value, method, (ReadOnlySpan<JValue>)args);
    public static T CallMethod<T>(JObject value, JMethodID method, ReadOnlySpan<JValue> args)
    {
        var info = method.Require(false);
        ValidateCall(method, args.Length, GetTypeSignature<T>());
        fixed (JValue* values = args)
        {
            if (typeof(T) == typeof(bool)) return (T)(object)JniEnvironment.InstanceMethods.CallBooleanMethod(Ref(value), info, (JniArgumentValue*)values);
            if (typeof(T) == typeof(sbyte)) return (T)(object)JniEnvironment.InstanceMethods.CallByteMethod(Ref(value), info, (JniArgumentValue*)values);
            if (typeof(T) == typeof(char)) return (T)(object)JniEnvironment.InstanceMethods.CallCharMethod(Ref(value), info, (JniArgumentValue*)values);
            if (typeof(T) == typeof(short)) return (T)(object)JniEnvironment.InstanceMethods.CallShortMethod(Ref(value), info, (JniArgumentValue*)values);
            if (typeof(T) == typeof(int)) return (T)(object)JniEnvironment.InstanceMethods.CallIntMethod(Ref(value), info, (JniArgumentValue*)values);
            if (typeof(T) == typeof(long)) return (T)(object)JniEnvironment.InstanceMethods.CallLongMethod(Ref(value), info, (JniArgumentValue*)values);
            if (typeof(T) == typeof(float)) return (T)(object)JniEnvironment.InstanceMethods.CallFloatMethod(Ref(value), info, (JniArgumentValue*)values);
            if (typeof(T) == typeof(double)) return (T)(object)JniEnvironment.InstanceMethods.CallDoubleMethod(Ref(value), info, (JniArgumentValue*)values);
            throw new ArgumentException("Unsupported Java primitive type.");
        }
    }

    public static T CallStaticObjectMethod<T>(JClass type, JMethodID method, params JValue[] args) where T : JObject, new() =>
        CallStaticObjectMethod<T>(type, method, (ReadOnlySpan<JValue>)args);
    public static T CallStaticObjectMethod<T>(JClass type, JMethodID method, ReadOnlySpan<JValue> args) where T : JObject, new()
    {
        var info = method.Require(true);
        ValidateCall(method, args.Length, "object");
        fixed (JValue* values = args)
        {
            return Global<T>(JniEnvironment.StaticMethods.CallStaticObjectMethod(Ref(type), info, (JniArgumentValue*)values));
        }
    }

    public static void CallStaticVoidMethod(JClass type, JMethodID method, params JValue[] args) =>
        CallStaticVoidMethod(type, method, (ReadOnlySpan<JValue>)args);
    public static void CallStaticVoidMethod(JClass type, JMethodID method, ReadOnlySpan<JValue> args)
    {
        var info = method.Require(true);
        ValidateCall(method, args.Length, "V");
        fixed (JValue* values = args)
        {
            JniEnvironment.StaticMethods.CallStaticVoidMethod(Ref(type), info, (JniArgumentValue*)values);
        }
    }

    public static T CallStaticMethod<T>(JClass type, JMethodID method, params JValue[] args) =>
        CallStaticMethod<T>(type, method, (ReadOnlySpan<JValue>)args);
    public static T CallStaticMethod<T>(JClass type, JMethodID method, ReadOnlySpan<JValue> args)
    {
        var info = method.Require(true);
        ValidateCall(method, args.Length, GetTypeSignature<T>());
        fixed (JValue* values = args)
        {
            if (typeof(T) == typeof(bool)) return (T)(object)JniEnvironment.StaticMethods.CallStaticBooleanMethod(Ref(type), info, (JniArgumentValue*)values);
            if (typeof(T) == typeof(sbyte)) return (T)(object)JniEnvironment.StaticMethods.CallStaticByteMethod(Ref(type), info, (JniArgumentValue*)values);
            if (typeof(T) == typeof(char)) return (T)(object)JniEnvironment.StaticMethods.CallStaticCharMethod(Ref(type), info, (JniArgumentValue*)values);
            if (typeof(T) == typeof(short)) return (T)(object)JniEnvironment.StaticMethods.CallStaticShortMethod(Ref(type), info, (JniArgumentValue*)values);
            if (typeof(T) == typeof(int)) return (T)(object)JniEnvironment.StaticMethods.CallStaticIntMethod(Ref(type), info, (JniArgumentValue*)values);
            if (typeof(T) == typeof(long)) return (T)(object)JniEnvironment.StaticMethods.CallStaticLongMethod(Ref(type), info, (JniArgumentValue*)values);
            if (typeof(T) == typeof(float)) return (T)(object)JniEnvironment.StaticMethods.CallStaticFloatMethod(Ref(type), info, (JniArgumentValue*)values);
            if (typeof(T) == typeof(double)) return (T)(object)JniEnvironment.StaticMethods.CallStaticDoubleMethod(Ref(type), info, (JniArgumentValue*)values);
            throw new ArgumentException("Unsupported Java primitive type.");
        }
    }

    public static T CallNonvirtualObjectMethod<T>(JObject value, JClass type, JMethodID method, params JValue[] args) where T : JObject, new() =>
        CallNonvirtualObjectMethod<T>(value, type, method, (ReadOnlySpan<JValue>)args);
    public static T CallNonvirtualObjectMethod<T>(JObject value, JClass type, JMethodID method, ReadOnlySpan<JValue> args) where T : JObject, new()
    {
        var info = method.Require(false);
        ValidateCall(method, args.Length, "object");
        fixed (JValue* values = args)
        {
            return Global<T>(JniEnvironment.InstanceMethods.CallNonvirtualObjectMethod(Ref(value), Ref(type), info, (JniArgumentValue*)values));
        }
    }

    public static void CallNonvirtualVoidMethod(JObject value, JClass type, JMethodID method, params JValue[] args) =>
        CallNonvirtualVoidMethod(value, type, method, (ReadOnlySpan<JValue>)args);
    public static void CallNonvirtualVoidMethod(JObject value, JClass type, JMethodID method, ReadOnlySpan<JValue> args)
    {
        var info = method.Require(false);
        ValidateCall(method, args.Length, "V");
        fixed (JValue* values = args)
        {
            JniEnvironment.InstanceMethods.CallNonvirtualVoidMethod(Ref(value), Ref(type), info, (JniArgumentValue*)values);
        }
    }

    public static T CallNonvirtualMethod<T>(JObject value, JClass type, JMethodID method, params JValue[] args) =>
        CallNonvirtualMethod<T>(value, type, method, (ReadOnlySpan<JValue>)args);
    public static T CallNonvirtualMethod<T>(JObject value, JClass type, JMethodID method, ReadOnlySpan<JValue> args)
    {
        var info = method.Require(false);
        ValidateCall(method, args.Length, GetTypeSignature<T>());
        fixed (JValue* values = args)
        {
            if (typeof(T) == typeof(bool)) return (T)(object)JniEnvironment.InstanceMethods.CallNonvirtualBooleanMethod(Ref(value), Ref(type), info, (JniArgumentValue*)values);
            if (typeof(T) == typeof(sbyte)) return (T)(object)JniEnvironment.InstanceMethods.CallNonvirtualByteMethod(Ref(value), Ref(type), info, (JniArgumentValue*)values);
            if (typeof(T) == typeof(char)) return (T)(object)JniEnvironment.InstanceMethods.CallNonvirtualCharMethod(Ref(value), Ref(type), info, (JniArgumentValue*)values);
            if (typeof(T) == typeof(short)) return (T)(object)JniEnvironment.InstanceMethods.CallNonvirtualShortMethod(Ref(value), Ref(type), info, (JniArgumentValue*)values);
            if (typeof(T) == typeof(int)) return (T)(object)JniEnvironment.InstanceMethods.CallNonvirtualIntMethod(Ref(value), Ref(type), info, (JniArgumentValue*)values);
            if (typeof(T) == typeof(long)) return (T)(object)JniEnvironment.InstanceMethods.CallNonvirtualLongMethod(Ref(value), Ref(type), info, (JniArgumentValue*)values);
            if (typeof(T) == typeof(float)) return (T)(object)JniEnvironment.InstanceMethods.CallNonvirtualFloatMethod(Ref(value), Ref(type), info, (JniArgumentValue*)values);
            if (typeof(T) == typeof(double)) return (T)(object)JniEnvironment.InstanceMethods.CallNonvirtualDoubleMethod(Ref(value), Ref(type), info, (JniArgumentValue*)values);
            throw new ArgumentException("Unsupported Java primitive type.");
        }
    }

    public static T GetField<T>(JObject value, JFieldID field)
    {
        var reference = Ref(value);
        ValidateField(field, GetTypeSignature<T>());
        var info = field.Require(false);
        if (typeof(T) == typeof(bool)) return (T)(object)JniEnvironment.InstanceFields.GetBooleanField(reference, info);
        if (typeof(T) == typeof(sbyte)) return (T)(object)JniEnvironment.InstanceFields.GetByteField(reference, info);
        if (typeof(T) == typeof(char)) return (T)(object)JniEnvironment.InstanceFields.GetCharField(reference, info);
        if (typeof(T) == typeof(short)) return (T)(object)JniEnvironment.InstanceFields.GetShortField(reference, info);
        if (typeof(T) == typeof(int)) return (T)(object)JniEnvironment.InstanceFields.GetIntField(reference, info);
        if (typeof(T) == typeof(long)) return (T)(object)JniEnvironment.InstanceFields.GetLongField(reference, info);
        if (typeof(T) == typeof(float)) return (T)(object)JniEnvironment.InstanceFields.GetFloatField(reference, info);
        if (typeof(T) == typeof(double)) return (T)(object)JniEnvironment.InstanceFields.GetDoubleField(reference, info);
        throw new ArgumentException("Unsupported Java primitive type.");
    }

    public static void SetField<T>(JObject value, JFieldID field, T data)
    {
        var reference = Ref(value);
        ValidateField(field, GetTypeSignature<T>());
        var info = field.Require(false);
        if (typeof(T) == typeof(bool)) { JniEnvironment.InstanceFields.SetBooleanField(reference, info, (bool)(object)data!); return; }
        if (typeof(T) == typeof(sbyte)) { JniEnvironment.InstanceFields.SetByteField(reference, info, (sbyte)(object)data!); return; }
        if (typeof(T) == typeof(char)) { JniEnvironment.InstanceFields.SetCharField(reference, info, (char)(object)data!); return; }
        if (typeof(T) == typeof(short)) { JniEnvironment.InstanceFields.SetShortField(reference, info, (short)(object)data!); return; }
        if (typeof(T) == typeof(int)) { JniEnvironment.InstanceFields.SetIntField(reference, info, (int)(object)data!); return; }
        if (typeof(T) == typeof(long)) { JniEnvironment.InstanceFields.SetLongField(reference, info, (long)(object)data!); return; }
        if (typeof(T) == typeof(float)) { JniEnvironment.InstanceFields.SetFloatField(reference, info, (float)(object)data!); return; }
        if (typeof(T) == typeof(double)) { JniEnvironment.InstanceFields.SetDoubleField(reference, info, (double)(object)data!); return; }
        throw new ArgumentException("Unsupported Java primitive type.");
    }

    public static T GetStaticField<T>(JClass type, JFieldID field)
    {
        var reference = Ref(type);
        ValidateField(field, GetTypeSignature<T>());
        var info = field.Require(true);
        if (typeof(T) == typeof(bool)) return (T)(object)JniEnvironment.StaticFields.GetStaticBooleanField(reference, info);
        if (typeof(T) == typeof(sbyte)) return (T)(object)JniEnvironment.StaticFields.GetStaticByteField(reference, info);
        if (typeof(T) == typeof(char)) return (T)(object)JniEnvironment.StaticFields.GetStaticCharField(reference, info);
        if (typeof(T) == typeof(short)) return (T)(object)JniEnvironment.StaticFields.GetStaticShortField(reference, info);
        if (typeof(T) == typeof(int)) return (T)(object)JniEnvironment.StaticFields.GetStaticIntField(reference, info);
        if (typeof(T) == typeof(long)) return (T)(object)JniEnvironment.StaticFields.GetStaticLongField(reference, info);
        if (typeof(T) == typeof(float)) return (T)(object)JniEnvironment.StaticFields.GetStaticFloatField(reference, info);
        if (typeof(T) == typeof(double)) return (T)(object)JniEnvironment.StaticFields.GetStaticDoubleField(reference, info);
        throw new ArgumentException("Unsupported Java primitive type.");
    }

    public static void SetStaticField<T>(JClass type, JFieldID field, T data)
    {
        var reference = Ref(type);
        ValidateField(field, GetTypeSignature<T>());
        var info = field.Require(true);
        if (typeof(T) == typeof(bool)) { JniEnvironment.StaticFields.SetStaticBooleanField(reference, info, (bool)(object)data!); return; }
        if (typeof(T) == typeof(sbyte)) { JniEnvironment.StaticFields.SetStaticByteField(reference, info, (sbyte)(object)data!); return; }
        if (typeof(T) == typeof(char)) { JniEnvironment.StaticFields.SetStaticCharField(reference, info, (char)(object)data!); return; }
        if (typeof(T) == typeof(short)) { JniEnvironment.StaticFields.SetStaticShortField(reference, info, (short)(object)data!); return; }
        if (typeof(T) == typeof(int)) { JniEnvironment.StaticFields.SetStaticIntField(reference, info, (int)(object)data!); return; }
        if (typeof(T) == typeof(long)) { JniEnvironment.StaticFields.SetStaticLongField(reference, info, (long)(object)data!); return; }
        if (typeof(T) == typeof(float)) { JniEnvironment.StaticFields.SetStaticFloatField(reference, info, (float)(object)data!); return; }
        if (typeof(T) == typeof(double)) { JniEnvironment.StaticFields.SetStaticDoubleField(reference, info, (double)(object)data!); return; }
        throw new ArgumentException("Unsupported Java primitive type.");
    }

}
#endif

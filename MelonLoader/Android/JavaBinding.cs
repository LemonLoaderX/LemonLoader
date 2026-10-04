#if ANDROID
#nullable enable
using System;
using Java.Interop;

namespace MelonLoader.Android;

/// <summary>Resolve Java members once as typed delegates; marshal with Java.Interop.</summary>
public static class JavaBinding
{
    public static TDelegate BindStatic<TDelegate>(string javaClass, string method) where TDelegate : Delegate =>
        JavaMethodBinding.Bind<TDelegate>(javaClass, method, JavaInvocationKind.Static);
    /// <summary>The delegate's first argument is the Java receiver; subsequent arguments map to Java parameters.</summary>
    public static TDelegate BindInstance<TDelegate>(string javaClass, string method) where TDelegate : Delegate =>
        JavaMethodBinding.Bind<TDelegate>(javaClass, method, JavaInvocationKind.Instance);
    public static TDelegate BindConstructor<TDelegate>(string javaClass) where TDelegate : Delegate =>
        JavaMethodBinding.Bind<TDelegate>(javaClass, "<init>", JavaInvocationKind.Constructor);
    public static T? GetStaticField<T>(string javaClass, string name)
    {
        JavaTypeMapping.ValidateClassName(javaClass);
        JavaTypeMapping.ValidateMemberName(name);
        using var thread = AndroidJava.AttachCurrentThread();
        var members = JavaMethodBinding.GetMembers(javaClass);
        string member = name + "." + JavaTypeMapping.GetDescriptor(typeof(T));
        if (typeof(T) == typeof(bool))
            return (T)(object)members.StaticFields.GetBooleanValue(member);
        if (typeof(T) == typeof(sbyte))
            return (T)(object)members.StaticFields.GetSByteValue(member);
        if (typeof(T) == typeof(char))
            return (T)(object)members.StaticFields.GetCharValue(member);
        if (typeof(T) == typeof(short))
            return (T)(object)members.StaticFields.GetInt16Value(member);
        if (typeof(T) == typeof(int))
            return (T)(object)members.StaticFields.GetInt32Value(member);
        if (typeof(T) == typeof(long))
            return (T)(object)members.StaticFields.GetInt64Value(member);
        if (typeof(T) == typeof(float))
            return (T)(object)members.StaticFields.GetSingleValue(member);
        if (typeof(T) == typeof(double))
            return (T)(object)members.StaticFields.GetDoubleValue(member);
        var value = members.StaticFields.GetObjectValue(member);
        return JavaObjectMarshaling.ReadLocalResult<T>(ref value);
    }
}
#endif

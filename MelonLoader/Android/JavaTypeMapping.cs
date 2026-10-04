#if ANDROID
#nullable enable
using System;
using System.Linq;
using Java.Interop;

namespace MelonLoader.Android;

/// <summary>Shared descriptor rules for bindings and interface callbacks.</summary>
internal static class JavaTypeMapping
{
    internal static string GetDescriptor(Type type)
    {
        if (type == typeof(void)) return "V";
        if (type == typeof(object) || type == typeof(IJavaPeerable)) return "Ljava/lang/Object;";
        if (type.IsArray)
        {
            if (type.GetArrayRank() != 1) throw new ArgumentException("Use jagged arrays for nested Java arrays.");
            return "[" + GetDescriptor(type.GetElementType()!);
        }
        if (type.IsEnum || type.IsByRef || type.IsPointer) throw new ArgumentException("Use the exact Java primitive or peer type: " + type.FullName);
        var signature = AndroidJava.Runtime.TypeManager.GetTypeSignature(type);
        if (!signature.IsValid) throw new ArgumentException("No Java type mapping exists for " + type.FullName);
        if (signature.ArrayRank == 0 && signature.QualifiedReference.Length == 1 &&
            type != typeof(bool) && type != typeof(sbyte) && type != typeof(char) && type != typeof(short) &&
            type != typeof(int) && type != typeof(long) && type != typeof(float) && type != typeof(double))
            throw new ArgumentException("Unsupported Java primitive: " + type.FullName);
        return signature.QualifiedReference;
    }

    internal static string GetMethodDescriptor(Type[] parameters, Type result) =>
        "(" + string.Concat(parameters.Select(GetDescriptor)) + ")" + GetDescriptor(result);

    internal static void ValidateClassName(string javaClass)
    {
        if (string.IsNullOrWhiteSpace(javaClass) || javaClass.StartsWith('/') || javaClass.EndsWith('/') ||
            javaClass.Contains("//") || javaClass.IndexOfAny(new[] { '.', ';', '[', '(', ')', '\0' }) >= 0)
            throw new ArgumentException("Use a slash-separated Java class name.", nameof(javaClass));
    }

    internal static void ValidateMemberName(string member)
    {
        if (string.IsNullOrWhiteSpace(member) || member.IndexOfAny(new[] { '.', ';', '/', '[', '(', ')', '<', '>', '\0' }) >= 0)
            throw new ArgumentException("Use an unqualified Java member name.", nameof(member));
    }
}
#endif

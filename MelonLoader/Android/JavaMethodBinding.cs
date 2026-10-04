#if ANDROID
#nullable enable
using System;
using System.Collections.Concurrent;
using System.Linq;
using System.Linq.Expressions;
using System.Reflection;
using Java.Interop;

namespace MelonLoader.Android;

internal static class JavaMethodBinding
{
    private readonly record struct BindingKey(Type Delegate, string Class, string Member, JavaInvocationKind Kind);
    private static readonly ConcurrentDictionary<BindingKey, Lazy<Delegate>> methods = new();
    private static readonly ConcurrentDictionary<string, JniPeerMembers> types = new(StringComparer.Ordinal);
    internal static JniPeerMembers GetMembers(string name) =>
        types.GetOrAdd(name, static value => new JniPeerMembers(value, typeof(JavaObject)));

    internal static TDelegate Bind<TDelegate>(string javaClass, string member, JavaInvocationKind kind) where TDelegate : Delegate
    {
        JavaTypeMapping.ValidateClassName(javaClass);
        if (kind != JavaInvocationKind.Constructor) JavaTypeMapping.ValidateMemberName(member);
        using var thread = AndroidJava.AttachCurrentThread();
        var key = new BindingKey(typeof(TDelegate), javaClass, member, kind);
        var binding = methods.GetOrAdd(key, static k => new Lazy<Delegate>(() => Compile(k)));
        try { return (TDelegate)binding.Value; }
        catch
        {
            methods.TryRemove(new System.Collections.Generic.KeyValuePair<BindingKey, Lazy<Delegate>>(key, binding));
            throw;
        }
    }

    private static Delegate Compile(BindingKey key)
    {
        var invoke = key.Delegate.GetMethod("Invoke")!;
        var parameters = invoke.GetParameters().Select(p => Expression.Parameter(p.ParameterType, p.Name)).ToArray();
        if (parameters.Any(p => p.Type.IsByRef || p.Type.IsPointer))
            throw new ArgumentException("Java delegates cannot contain pointers or ref parameters.");
        int skip = key.Kind == JavaInvocationKind.Instance ? 1 : 0;
        if (skip != 0 && (parameters.Length == 0 || !typeof(IJavaPeerable).IsAssignableFrom(parameters[0].Type)))
            throw new ArgumentException("Instance delegates require an IJavaPeerable receiver as their first argument.");
        if (key.Kind == JavaInvocationKind.Constructor && !typeof(IJavaPeerable).IsAssignableFrom(invoke.ReturnType))
            throw new ArgumentException("Constructors return a Java peer type.");
        var arguments = parameters.Skip(skip).ToArray();
        string signature = JavaTypeMapping.GetMethodDescriptor(arguments.Select(p => p.Type).ToArray(),
            key.Kind == JavaInvocationKind.Constructor ? typeof(void) : invoke.ReturnType);
        var members = types.GetOrAdd(key.Class, static name => new JniPeerMembers(name, typeof(JavaObject)));
        if (key.Kind == JavaInvocationKind.Constructor)
        {
            var resultSignature = AndroidJava.Runtime.TypeManager.GetTypeSignature(invoke.ReturnType);
            if (!resultSignature.IsValid || resultSignature.ArrayRank != 0 || resultSignature.SimpleReference == null)
                throw new ArgumentException("Constructors require a mapped Java object return type.");
            using var resultType = new JniType(resultSignature.SimpleReference);
            if (!JniEnvironment.Types.IsAssignableFrom(members.JniPeerType.PeerReference, resultType.PeerReference))
                throw new ArgumentException("Constructor return type cannot represent " + key.Class + ".");
        }
        var call = new JavaBoundMethod(members, key.Member + "." + signature, key.Kind, arguments.Select(p => p.Type).ToArray(), signature);
        // Resolve at binding time: missing members fail before callers enter native code.
        if (key.Kind == JavaInvocationKind.Static) members.StaticMethods.GetMethodInfo(call.Member);
        else members.InstanceMethods.GetMethodInfo(call.Member);
        var returnType = invoke.ReturnType == typeof(void) ? typeof(JavaVoidResult) : invoke.ReturnType;
        var genericTypes = arguments.Select(p => p.Type).Prepend(returnType).ToArray();
        bool many = arguments.Length > 6;
        var bridge = typeof(JavaInvocation).GetMethod(many ? "CallMany" : "Call" + arguments.Length,
            BindingFlags.NonPublic | BindingFlags.Static)!.MakeGenericMethod(many ? new[] { returnType } : genericTypes);
        var expressions = new System.Collections.Generic.List<Expression> { Expression.Constant(call),
            skip == 0 ? Expression.Constant(null, typeof(IJavaPeerable)) : Expression.Convert(parameters[0], typeof(IJavaPeerable)) };
        if (many) expressions.Add(Expression.NewArrayInit(typeof(object), arguments.Select(p => Expression.Convert(p, typeof(object)))));
        else expressions.AddRange(arguments);
        Expression body = Expression.Call(bridge, expressions);
        if (invoke.ReturnType == typeof(void)) body = Expression.Block(body, Expression.Empty());
        return Expression.Lambda(key.Delegate, body, parameters).Compile();
    }
}
#endif

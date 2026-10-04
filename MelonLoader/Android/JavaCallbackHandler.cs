#if ANDROID
#nullable enable
using System;
using System.Linq;
using System.Linq.Expressions;
using Java.Interop;

namespace MelonLoader.Android;

/// <summary>One resolved method, its delegate and invocation ownership.</summary>
internal sealed class JavaCallbackHandler
{
    internal string Member { get; }
    private readonly Type[] parameterTypes;
    private readonly Type returnType;
    private readonly Func<object?[], object?> invoke;

    internal JavaCallbackHandler(JavaCallbackMethod method)
    {
        ArgumentNullException.ThrowIfNull(method.Handler);
        JavaTypeMapping.ValidateMemberName(method.Name);
        var definition = method.Handler.GetType().GetMethod("Invoke")!;
        parameterTypes = definition.GetParameters().Select(p => p.ParameterType).ToArray();
        returnType = definition.ReturnType;
        if (parameterTypes.Any(t => t.IsByRef || t.IsPointer) || returnType.IsByRef || returnType.IsPointer)
            throw new ArgumentException("Callback delegates cannot contain pointers or ref values.");
        Member = method.Name + "." + JavaTypeMapping.GetMethodDescriptor(parameterTypes, returnType);

        var values = Expression.Parameter(typeof(object[]), "values");
        var call = Expression.Invoke(Expression.Constant(method.Handler),
            parameterTypes.Select((t, i) => Expression.Convert(Expression.ArrayIndex(values, Expression.Constant(i)), t)));
        Expression result = returnType == typeof(void)
            ? Expression.Block(call, Expression.Constant(null, typeof(object)))
            : Expression.Convert(call, typeof(object));
        invoke = Expression.Lambda<Func<object?[], object?>>(result, values).Compile();
    }

    internal nint InvokeAndReturn(JniObjectReference arguments)
    {
        // Keep borrowed arguments alive until a returned reference has been copied.
        using var scope = new JavaObjectMarshaling.CallbackArguments(arguments, parameterTypes);
        var result = invoke(scope.Values);
        if (returnType == typeof(void)) return 0;
        var reference = AndroidJava.Runtime.ValueManager.CreateLocalObjectReferenceArgument(returnType, result);
        try { return JniEnvironment.References.NewReturnToJniRef(reference); }
        finally { JniObjectReference.Dispose(ref reference); }
    }
}
#endif

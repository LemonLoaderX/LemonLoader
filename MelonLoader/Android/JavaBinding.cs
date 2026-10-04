#if ANDROID
#nullable enable
using System;
using System.Collections.Concurrent;
using System.Linq;
using System.Linq.Expressions;
using System.Reflection;
using Java.Interop;

namespace MelonLoader.Android;

/// <summary>Resolve Java members once as typed delegates; marshal with Java.Interop.</summary>
public static unsafe class JavaBinding
{
    private enum Kind { Static, Instance, Constructor }
    private readonly record struct Key(Type Delegate, string Class, string Member, Kind Kind);
    private static readonly ConcurrentDictionary<Key, Delegate> methods = new();
    private static readonly ConcurrentDictionary<string, JniPeerMembers> types = new(StringComparer.Ordinal);

    public static TDelegate BindStatic<TDelegate>(string javaClass, string method) where TDelegate : Delegate =>
        Bind<TDelegate>(javaClass, method, Kind.Static);
    /// <summary>The delegate's first argument is the Java receiver; subsequent arguments map to Java parameters.</summary>
    public static TDelegate BindInstance<TDelegate>(string javaClass, string method) where TDelegate : Delegate =>
        Bind<TDelegate>(javaClass, method, Kind.Instance);
    public static TDelegate BindConstructor<TDelegate>(string javaClass) where TDelegate : Delegate =>
        Bind<TDelegate>(javaClass, "<init>", Kind.Constructor);

    private static TDelegate Bind<TDelegate>(string javaClass, string member, Kind kind) where TDelegate : Delegate
    {
        if (string.IsNullOrWhiteSpace(javaClass) || javaClass.Contains('.') || javaClass.Contains(';'))
            throw new ArgumentException("Use a slash-separated Java class name.", nameof(javaClass));
        if (string.IsNullOrWhiteSpace(member)) throw new ArgumentException("Member name is required.", nameof(member));
        using var thread = AndroidJava.AttachCurrentThread();
        var key = new Key(typeof(TDelegate), javaClass, member, kind);
        return (TDelegate)methods.GetOrAdd(key, static k => Compile(k));
    }

    private static Delegate Compile(Key key)
    {
        var invoke = key.Delegate.GetMethod("Invoke")!;
        var parameters = invoke.GetParameters().Select(p => Expression.Parameter(p.ParameterType, p.Name)).ToArray();
        if (parameters.Any(p => p.Type.IsByRef || p.Type.IsPointer)) throw new ArgumentException("Java delegates cannot contain pointers or ref parameters.");
        int skip = key.Kind == Kind.Instance ? 1 : 0;
        if (skip != 0 && (parameters.Length == 0 || !typeof(IJavaPeerable).IsAssignableFrom(parameters[0].Type)))
            throw new ArgumentException("Instance delegates require an IJavaPeerable receiver as their first argument.");
        if (key.Kind == Kind.Constructor && !typeof(IJavaPeerable).IsAssignableFrom(invoke.ReturnType))
            throw new ArgumentException("Constructors return a Java peer type.");
        var arguments = parameters.Skip(skip).ToArray();
        string signature = "(" + string.Concat(arguments.Select(p => Signature(p.Type))) + ")" +
            (key.Kind == Kind.Constructor ? "V" : Signature(invoke.ReturnType));
        var members = types.GetOrAdd(key.Class, static name => new JniPeerMembers(name, typeof(JavaObject)));
        var call = new Call(members, key.Member + "." + signature, key.Kind, arguments.Select(p => p.Type).ToArray());
        // Resolve at binding time: missing members fail before callers enter native code.
        if (key.Kind == Kind.Static) members.StaticMethods.GetMethodInfo(call.Member);
        else members.InstanceMethods.GetMethodInfo(call.Member);
        var returnType = invoke.ReturnType == typeof(void) ? typeof(VoidResult) : invoke.ReturnType;
        var genericTypes = arguments.Select(p => p.Type).Prepend(returnType).ToArray();
        bool many = arguments.Length > 6;
        var bridge = typeof(JavaBinding).GetMethod(many ? "CallMany" : "Call" + arguments.Length,
            BindingFlags.NonPublic | BindingFlags.Static)!.MakeGenericMethod(many ? new[] { returnType } : genericTypes);
        var expressions = new System.Collections.Generic.List<Expression> { Expression.Constant(call),
            skip == 0 ? Expression.Constant(null, typeof(IJavaPeerable)) : Expression.Convert(parameters[0], typeof(IJavaPeerable)) };
        if (many) expressions.Add(Expression.NewArrayInit(typeof(object), arguments.Select(p => Expression.Convert(p, typeof(object)))));
        else expressions.AddRange(arguments);
        Expression body = Expression.Call(bridge, expressions);
        if (invoke.ReturnType == typeof(void)) body = Expression.Block(body, Expression.Empty());
        return Expression.Lambda(key.Delegate, body, parameters).Compile();
    }

    internal static string Signature(Type type)
    {
        if (type == typeof(void)) return "V";
        if (type.IsArray) _ = Signature(type.GetElementType()!);
        if (type.IsEnum || type.IsByRef || type.IsPointer) throw new ArgumentException("Use the exact Java primitive or peer type: " + type.FullName);
        var signature = AndroidJava.Runtime.TypeManager.GetTypeSignature(type);
        if (!signature.IsValid) throw new ArgumentException("No Java type mapping exists for " + type.FullName);
        if (signature.ArrayRank == 0 && signature.QualifiedReference.Length == 1 &&
            type != typeof(bool) && type != typeof(sbyte) && type != typeof(char) && type != typeof(short) &&
            type != typeof(int) && type != typeof(long) && type != typeof(float) && type != typeof(double))
            throw new ArgumentException("Unsupported Java primitive: " + type.FullName);
        return signature.QualifiedReference;
    }

    private sealed record Call(JniPeerMembers Members, string Member, Kind Kind, Type[] Arguments);
    private readonly struct VoidResult { }
    private ref struct Argument<T>
    {
        private readonly T value;
        private readonly JniValueMarshaler<T> marshaler;
        private JniValueMarshalerState state;
        internal Argument(T value)
        {
            if (value is IJavaPeerable peer && !peer.PeerReference.IsValid) throw new ObjectDisposedException(peer.GetType().Name);
            this.value = value;
            marshaler = AndroidJava.Runtime.ValueManager.GetValueMarshaler<T>();
            state = marshaler.CreateGenericArgumentState(value);
        }
        internal JniArgumentValue Value => state.JniArgumentValue;
        public void Dispose() => marshaler.DestroyGenericArgumentState(value, ref state);
    }

    private static T Invoke<T>(Call call, IJavaPeerable? self, JniArgumentValue* args)
    {
        if (call.Kind == Kind.Instance && (self == null || !self.PeerReference.IsValid))
            throw new ObjectDisposedException("Java receiver");
        var members = call.Members;
        bool isStatic = call.Kind == Kind.Static;
        if (call.Kind == Kind.Constructor)
        {
            string signature = call.Member.Substring(7);
            var peer = JniEnvironment.Object.NewObject(members.JniPeerType.PeerReference,
                members.JniPeerType.GetInstanceMethod("<init>", signature), args);
            return AndroidJava.Runtime.ValueManager.CreateValue<T>(ref peer, JniObjectReferenceOptions.CopyAndDispose)!;
        }
        if (typeof(T) == typeof(VoidResult))
        {
            if (isStatic) members.StaticMethods.InvokeVoidMethod(call.Member, args);
            else members.InstanceMethods.InvokeAbstractVoidMethod(call.Member, self!, args);
            GC.KeepAlive(self);
            return default!;
        }
        if (typeof(T) == typeof(bool)) return (T)(object)(isStatic ? members.StaticMethods.InvokeBooleanMethod(call.Member, args) : members.InstanceMethods.InvokeAbstractBooleanMethod(call.Member, self!, args));
        if (typeof(T) == typeof(sbyte)) return (T)(object)(isStatic ? members.StaticMethods.InvokeSByteMethod(call.Member, args) : members.InstanceMethods.InvokeAbstractSByteMethod(call.Member, self!, args));
        if (typeof(T) == typeof(char)) return (T)(object)(isStatic ? members.StaticMethods.InvokeCharMethod(call.Member, args) : members.InstanceMethods.InvokeAbstractCharMethod(call.Member, self!, args));
        if (typeof(T) == typeof(short)) return (T)(object)(isStatic ? members.StaticMethods.InvokeInt16Method(call.Member, args) : members.InstanceMethods.InvokeAbstractInt16Method(call.Member, self!, args));
        if (typeof(T) == typeof(int)) return (T)(object)(isStatic ? members.StaticMethods.InvokeInt32Method(call.Member, args) : members.InstanceMethods.InvokeAbstractInt32Method(call.Member, self!, args));
        if (typeof(T) == typeof(long)) return (T)(object)(isStatic ? members.StaticMethods.InvokeInt64Method(call.Member, args) : members.InstanceMethods.InvokeAbstractInt64Method(call.Member, self!, args));
        if (typeof(T) == typeof(float)) return (T)(object)(isStatic ? members.StaticMethods.InvokeSingleMethod(call.Member, args) : members.InstanceMethods.InvokeAbstractSingleMethod(call.Member, self!, args));
        if (typeof(T) == typeof(double)) return (T)(object)(isStatic ? members.StaticMethods.InvokeDoubleMethod(call.Member, args) : members.InstanceMethods.InvokeAbstractDoubleMethod(call.Member, self!, args));
        var result = isStatic ? members.StaticMethods.InvokeObjectMethod(call.Member, args) :
            members.InstanceMethods.InvokeAbstractObjectMethod(call.Member, self!, args);
        return AndroidJava.Runtime.ValueManager.CreateValue<T>(ref result, JniObjectReferenceOptions.CopyAndDispose)!;
    }

    private static T Call0<T>(Call call, IJavaPeerable? self)
    {
        using var thread = AndroidJava.AttachCurrentThread();
        try { return Invoke<T>(call, self, null); }
        finally { GC.KeepAlive(self); }
    }

    private static T CallMany<T>(Call call, IJavaPeerable? self, object?[] values)
    {
        using var thread = AndroidJava.AttachCurrentThread();
        var marshalers = new JniValueMarshaler[values.Length];
        var states = new JniValueMarshalerState[values.Length];
        Span<JniArgumentValue> arguments = values.Length <= 64 ? stackalloc JniArgumentValue[values.Length] : new JniArgumentValue[values.Length];
        int initialized = 0;
        try
        {
            for (int i = 0; i < values.Length; i++)
            {
                if (values[i] is IJavaPeerable peer && !peer.PeerReference.IsValid) throw new ObjectDisposedException(peer.GetType().Name);
                marshalers[i] = AndroidJava.Runtime.ValueManager.GetValueMarshaler(call.Arguments[i]);
                states[i] = marshalers[i].CreateArgumentState(values[i]);
                initialized++;
                arguments[i] = states[i].JniArgumentValue;
            }
            fixed (JniArgumentValue* args = arguments) return Invoke<T>(call, self, args);
        }
        finally
        {
            for (int i = initialized - 1; i >= 0; i--) marshalers[i].DestroyArgumentState(values[i], ref states[i]);
            GC.KeepAlive(self);
        }
    }

    private static T Call1<T, T0>(Call call, IJavaPeerable? self, T0 value0)
    {
        using var thread = AndroidJava.AttachCurrentThread();
        using var a0 = new Argument<T0>(value0);
        JniArgumentValue* args = stackalloc JniArgumentValue[1] { a0.Value };
        try { return Invoke<T>(call, self, args); }
        finally { GC.KeepAlive(self); }
    }

    private static T Call2<T, T0, T1>(Call call, IJavaPeerable? self, T0 value0, T1 value1)
    {
        using var thread = AndroidJava.AttachCurrentThread();
        using var a0 = new Argument<T0>(value0);
        using var a1 = new Argument<T1>(value1);
        JniArgumentValue* args = stackalloc JniArgumentValue[2] { a0.Value, a1.Value };
        try { return Invoke<T>(call, self, args); }
        finally { GC.KeepAlive(self); }
    }

    private static T Call3<T, T0, T1, T2>(Call call, IJavaPeerable? self, T0 value0, T1 value1, T2 value2)
    {
        using var thread = AndroidJava.AttachCurrentThread();
        using var a0 = new Argument<T0>(value0);
        using var a1 = new Argument<T1>(value1);
        using var a2 = new Argument<T2>(value2);
        JniArgumentValue* args = stackalloc JniArgumentValue[3] { a0.Value, a1.Value, a2.Value };
        try { return Invoke<T>(call, self, args); }
        finally { GC.KeepAlive(self); }
    }

    private static T Call4<T, T0, T1, T2, T3>(Call call, IJavaPeerable? self, T0 value0, T1 value1, T2 value2, T3 value3)
    {
        using var thread = AndroidJava.AttachCurrentThread();
        using var a0 = new Argument<T0>(value0);
        using var a1 = new Argument<T1>(value1);
        using var a2 = new Argument<T2>(value2);
        using var a3 = new Argument<T3>(value3);
        JniArgumentValue* args = stackalloc JniArgumentValue[4] { a0.Value, a1.Value, a2.Value, a3.Value };
        try { return Invoke<T>(call, self, args); }
        finally { GC.KeepAlive(self); }
    }

    private static T Call5<T, T0, T1, T2, T3, T4>(Call call, IJavaPeerable? self, T0 value0, T1 value1, T2 value2, T3 value3, T4 value4)
    {
        using var thread = AndroidJava.AttachCurrentThread();
        using var a0 = new Argument<T0>(value0);
        using var a1 = new Argument<T1>(value1);
        using var a2 = new Argument<T2>(value2);
        using var a3 = new Argument<T3>(value3);
        using var a4 = new Argument<T4>(value4);
        JniArgumentValue* args = stackalloc JniArgumentValue[5] { a0.Value, a1.Value, a2.Value, a3.Value, a4.Value };
        try { return Invoke<T>(call, self, args); }
        finally { GC.KeepAlive(self); }
    }

    private static T Call6<T, T0, T1, T2, T3, T4, T5>(Call call, IJavaPeerable? self, T0 value0, T1 value1, T2 value2, T3 value3, T4 value4, T5 value5)
    {
        using var thread = AndroidJava.AttachCurrentThread();
        using var a0 = new Argument<T0>(value0);
        using var a1 = new Argument<T1>(value1);
        using var a2 = new Argument<T2>(value2);
        using var a3 = new Argument<T3>(value3);
        using var a4 = new Argument<T4>(value4);
        using var a5 = new Argument<T5>(value5);
        JniArgumentValue* args = stackalloc JniArgumentValue[6] { a0.Value, a1.Value, a2.Value, a3.Value, a4.Value, a5.Value };
        try { return Invoke<T>(call, self, args); }
        finally { GC.KeepAlive(self); }
    }

    public static T? GetStaticField<T>(string javaClass, string name)
    {
        using var thread = AndroidJava.AttachCurrentThread();
        var members = types.GetOrAdd(javaClass, static n => new JniPeerMembers(n, typeof(JavaObject)));
        string member = name + "." + Signature(typeof(T));
        if (typeof(T) == typeof(bool)) return (T)(object)members.StaticFields.GetBooleanValue(member);
        if (typeof(T) == typeof(sbyte)) return (T)(object)members.StaticFields.GetSByteValue(member);
        if (typeof(T) == typeof(char)) return (T)(object)members.StaticFields.GetCharValue(member);
        if (typeof(T) == typeof(short)) return (T)(object)members.StaticFields.GetInt16Value(member);
        if (typeof(T) == typeof(int)) return (T)(object)members.StaticFields.GetInt32Value(member);
        if (typeof(T) == typeof(long)) return (T)(object)members.StaticFields.GetInt64Value(member);
        if (typeof(T) == typeof(float)) return (T)(object)members.StaticFields.GetSingleValue(member);
        if (typeof(T) == typeof(double)) return (T)(object)members.StaticFields.GetDoubleValue(member);
        var value = members.StaticFields.GetObjectValue(member);
        return AndroidJava.Runtime.ValueManager.CreateValue<T>(ref value, JniObjectReferenceOptions.CopyAndDispose);
    }
}
#endif

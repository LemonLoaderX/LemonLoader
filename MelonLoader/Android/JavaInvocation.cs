#if ANDROID
#nullable enable
using System;
using Java.Interop;

namespace MelonLoader.Android;

internal enum JavaInvocationKind { Static, Instance, Constructor }
internal sealed record JavaBoundMethod(JniPeerMembers Members, string Member, JavaInvocationKind Kind, Type[] Arguments, string Signature);
internal readonly struct JavaVoidResult { }

internal static unsafe class JavaInvocation
{
    private ref struct Argument<T>
    {
        private readonly T value;
        private readonly JniValueMarshaler<T> marshaler;
        private JniValueMarshalerState state;
        internal Argument(T value)
        {
            if (value is IJavaPeerable peer && !peer.PeerReference.IsValid)
                throw new ObjectDisposedException(peer.GetType().Name);
            this.value = value;
            marshaler = AndroidJava.Runtime.ValueManager.GetValueMarshaler<T>();
            state = marshaler.CreateGenericArgumentState(value);
        }
        internal JniArgumentValue Value => state.JniArgumentValue;
        public void Dispose() => marshaler.DestroyGenericArgumentState(value, ref state);
    }

    private static T Invoke<T>(JavaBoundMethod call, IJavaPeerable? self, JniArgumentValue* args)
    {
        if (call.Kind == JavaInvocationKind.Instance && (self == null || !self.PeerReference.IsValid))
            throw new ObjectDisposedException("Java receiver");
        var members = call.Members;
        if (call.Kind == JavaInvocationKind.Instance && !JniEnvironment.Types.IsInstanceOf(self!.PeerReference, members.JniPeerType.PeerReference))
            throw new ArgumentException("Java receiver does not implement " + members.JniPeerTypeName + ".", nameof(self));
        bool isStatic = call.Kind == JavaInvocationKind.Static;
        if (call.Kind == JavaInvocationKind.Constructor)
        {
            var peer = JniEnvironment.Object.NewObject(members.JniPeerType.PeerReference,
                members.JniPeerType.GetInstanceMethod("<init>", call.Signature), args);
            return JavaObjectMarshaling.ReadLocalResult<T>(ref peer)!;
        }
        if (typeof(T) == typeof(JavaVoidResult))
        {
            if (isStatic) members.StaticMethods.InvokeVoidMethod(call.Member, args);
            else members.InstanceMethods.InvokeAbstractVoidMethod(call.Member, self!, args);
            GC.KeepAlive(self);
            return default!;
        }
        if (typeof(T) == typeof(bool))
            return (T)(object)(isStatic ? members.StaticMethods.InvokeBooleanMethod(call.Member, args) : members.InstanceMethods.InvokeAbstractBooleanMethod(call.Member, self!, args));
        if (typeof(T) == typeof(sbyte))
            return (T)(object)(isStatic ? members.StaticMethods.InvokeSByteMethod(call.Member, args) : members.InstanceMethods.InvokeAbstractSByteMethod(call.Member, self!, args));
        if (typeof(T) == typeof(char))
            return (T)(object)(isStatic ? members.StaticMethods.InvokeCharMethod(call.Member, args) : members.InstanceMethods.InvokeAbstractCharMethod(call.Member, self!, args));
        if (typeof(T) == typeof(short))
            return (T)(object)(isStatic ? members.StaticMethods.InvokeInt16Method(call.Member, args) : members.InstanceMethods.InvokeAbstractInt16Method(call.Member, self!, args));
        if (typeof(T) == typeof(int))
            return (T)(object)(isStatic ? members.StaticMethods.InvokeInt32Method(call.Member, args) : members.InstanceMethods.InvokeAbstractInt32Method(call.Member, self!, args));
        if (typeof(T) == typeof(long))
            return (T)(object)(isStatic ? members.StaticMethods.InvokeInt64Method(call.Member, args) : members.InstanceMethods.InvokeAbstractInt64Method(call.Member, self!, args));
        if (typeof(T) == typeof(float))
            return (T)(object)(isStatic ? members.StaticMethods.InvokeSingleMethod(call.Member, args) : members.InstanceMethods.InvokeAbstractSingleMethod(call.Member, self!, args));
        if (typeof(T) == typeof(double))
            return (T)(object)(isStatic ? members.StaticMethods.InvokeDoubleMethod(call.Member, args) : members.InstanceMethods.InvokeAbstractDoubleMethod(call.Member, self!, args));
        var result = isStatic ? members.StaticMethods.InvokeObjectMethod(call.Member, args) :
            members.InstanceMethods.InvokeAbstractObjectMethod(call.Member, self!, args);
        return JavaObjectMarshaling.ReadLocalResult<T>(ref result)!;
    }

    private static T Call0<T>(JavaBoundMethod call, IJavaPeerable? self)
    {
        using var thread = AndroidJava.AttachCurrentThread();
        try { return Invoke<T>(call, self, null); }
        finally { GC.KeepAlive(self); }
    }

    private static T CallMany<T>(JavaBoundMethod call, IJavaPeerable? self, object?[] values)
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
                if (values[i] is IJavaPeerable peer && !peer.PeerReference.IsValid)
                    throw new ObjectDisposedException(peer.GetType().Name);
                marshalers[i] = AndroidJava.Runtime.ValueManager.GetValueMarshaler(call.Arguments[i]);
                states[i] = marshalers[i].CreateArgumentState(values[i]);
                initialized++;
                arguments[i] = states[i].JniArgumentValue;
            }
            fixed (JniArgumentValue* args = arguments) return Invoke<T>(call, self, args);
        }
        finally
        {
            Exception? failure = null;
            for (int i = initialized - 1; i >= 0; i--)
            {
                try { marshalers[i].DestroyArgumentState(values[i], ref states[i]); }
                catch (Exception exception) { failure ??= exception; }
            }
            GC.KeepAlive(self);
            if (failure != null)
                System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(failure).Throw();
        }
    }

    private static T Call1<T, T0>(JavaBoundMethod call, IJavaPeerable? self, T0 value0)
    {
        using var thread = AndroidJava.AttachCurrentThread();
        using var a0 = new Argument<T0>(value0);
        JniArgumentValue* args = stackalloc JniArgumentValue[1] { a0.Value };
        try { return Invoke<T>(call, self, args); }
        finally { GC.KeepAlive(self); }
    }

    private static T Call2<T, T0, T1>(JavaBoundMethod call, IJavaPeerable? self, T0 value0, T1 value1)
    {
        using var thread = AndroidJava.AttachCurrentThread();
        using var a0 = new Argument<T0>(value0);
        using var a1 = new Argument<T1>(value1);
        JniArgumentValue* args = stackalloc JniArgumentValue[2] { a0.Value, a1.Value };
        try { return Invoke<T>(call, self, args); }
        finally { GC.KeepAlive(self); }
    }

    private static T Call3<T, T0, T1, T2>(JavaBoundMethod call, IJavaPeerable? self, T0 value0, T1 value1, T2 value2)
    {
        using var thread = AndroidJava.AttachCurrentThread();
        using var a0 = new Argument<T0>(value0);
        using var a1 = new Argument<T1>(value1);
        using var a2 = new Argument<T2>(value2);
        JniArgumentValue* args = stackalloc JniArgumentValue[3] { a0.Value, a1.Value, a2.Value };
        try { return Invoke<T>(call, self, args); }
        finally { GC.KeepAlive(self); }
    }

    private static T Call4<T, T0, T1, T2, T3>(JavaBoundMethod call, IJavaPeerable? self, T0 value0, T1 value1, T2 value2, T3 value3)
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

    private static T Call5<T, T0, T1, T2, T3, T4>(JavaBoundMethod call, IJavaPeerable? self, T0 value0, T1 value1, T2 value2, T3 value3, T4 value4)
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

    private static T Call6<T, T0, T1, T2, T3, T4, T5>(JavaBoundMethod call, IJavaPeerable? self, T0 value0, T1 value1, T2 value2, T3 value3, T4 value4, T5 value5)
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

}
#endif

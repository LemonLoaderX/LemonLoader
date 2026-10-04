#if ANDROID
#nullable enable
using System;
using System.Collections.Generic;
using Java.Interop;

namespace MelonLoader.Android;

/// <summary>Ownership rules for JNI results and invocation-scoped callback arguments.</summary>
internal static class JavaObjectMarshaling
{
    internal static T? ReadLocalResult<T>(ref JniObjectReference reference)
    {
        try
        {
            var value = AndroidJava.Runtime.ValueManager.CreateValue<T>(ref reference, JniObjectReferenceOptions.Copy);
            if (reference.IsValid && value == null)
                throw new InvalidCastException("Java result cannot be represented as " + typeof(T).FullName + ".");
            return value;
        }
        finally { JniObjectReference.Dispose(ref reference); }
    }

    internal ref struct CallbackArguments
    {
        private List<IJavaPeerable>? owned;
        internal object?[] Values { get; }

        internal CallbackArguments(JniObjectReference arguments, Type[] parameterTypes)
        {
            if (!arguments.IsValid || JniEnvironment.Arrays.GetArrayLength(arguments) != parameterTypes.Length)
                throw new ArgumentException("Java callback argument count differs.");
            Values = parameterTypes.Length == 0 ? Array.Empty<object?>() : new object?[parameterTypes.Length];
            try
            {
                for (int i = 0; i < Values.Length; i++)
                {
                    var item = JniEnvironment.Arrays.GetObjectArrayElement(arguments, i);
                    try { Values[i] = ReadArgument(item, parameterTypes[i]); }
                    finally { JniObjectReference.Dispose(ref item); }
                }
            }
            catch { Dispose(); throw; }
        }

        private object? ReadArgument(JniObjectReference reference, Type type, int depth = 0)
        {
            if (!reference.IsValid) return null;
            if (depth >= 64) throw new ArgumentException("Java callback array nesting exceeds the conversion limit.");
            if (type == typeof(object))
            {
                var name = JniEnvironment.Types.GetJniTypeNameFromInstance(reference);
                type = JniTypeSignature.TryParse(name!, out var signature)
                    ? AndroidJava.Runtime.TypeManager.GetType(signature) ?? typeof(JavaObject)
                    : typeof(JavaObject);
            }
            // Upstream array marshaling uses GetValue for elements, which can reuse a
            // caller's registered peer. Scoped callback arguments must own new peers.
            if (type.IsArray && !type.GetElementType()!.IsPrimitive)
            {
                var elementType = type.GetElementType()!;
                var array = Array.CreateInstance(elementType, JniEnvironment.Arrays.GetArrayLength(reference));
                for (int i = 0; i < array.Length; i++)
                {
                    var item = JniEnvironment.Arrays.GetObjectArrayElement(reference, i);
                    try { array.SetValue(ReadArgument(item, elementType, depth + 1), i); }
                    finally { JniObjectReference.Dispose(ref item); }
                }
                return array;
            }
            var manager = AndroidJava.Runtime.ValueManager;
            object? value = manager.CreateValue(ref reference, JniObjectReferenceOptions.CopyAndDoNotRegister, type);
            if (value == null) throw new InvalidCastException("Java callback argument cannot be represented as " + type.FullName + ".");
            if (value is IJavaPeerable peer) (owned ??= new List<IJavaPeerable>()).Add(peer);
            return value;
        }

        public void Dispose()
        {
            if (owned == null) return;
            Exception? failure = null;
            for (int i = owned.Count - 1; i >= 0; i--)
            {
                try { owned[i].Dispose(); }
                catch (Exception exception) { failure ??= exception; }
            }
            owned.Clear();
            owned = null;
            if (failure != null) System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(failure).Throw();
        }
    }
}
#endif

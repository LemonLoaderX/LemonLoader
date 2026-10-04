#if ANDROID
#nullable enable
using System;
using System.Collections.Generic;

namespace MelonLoader.Java;

/// <summary>A Java class with separate, synchronized instance and static member caches.</summary>
public class JClass : JObject
{
    internal sealed class Members
    {
        internal readonly Dictionary<(bool Static, string Name, string Signature), JMethodID> Methods = new();
        internal readonly Dictionary<(bool Static, string Name, string Signature), JFieldID> Fields = new();
    }
    private Members? cache;
    internal Members Cache
    {
        get
        {
            if (cache == null) System.Threading.Interlocked.CompareExchange(ref cache, new Members(), null);
            return cache;
        }
        set => cache = value;
    }

    private JMethodID Method(string name, string signature, bool isStatic)
    {
        ValidateAccess();
        lock (Cache)
        {
            var key = (isStatic, name, signature);
            if (!Cache.Methods.TryGetValue(key, out var id))
            {
                id = JNI.ResolveMethod(this, name, signature, isStatic);
                Cache.Methods.Add(key, id);
            }
            return id;
        }
    }

    private JFieldID Field(string name, string signature, bool isStatic)
    {
        ValidateAccess();
        lock (Cache)
        {
            var key = (isStatic, name, signature);
            if (!Cache.Fields.TryGetValue(key, out var id))
            {
                id = JNI.ResolveField(this, name, signature, isStatic);
                Cache.Fields.Add(key, id);
            }
            return id;
        }
    }

    public JMethodID GetMethodID(string name, string signature) => Method(name, signature, false);
    public JMethodID GetStaticMethodID(string name, string signature) => Method(name, signature, true);
    public JFieldID GetFieldID(string name, string signature) => Field(name, signature, false);
    public JFieldID GetStaticFieldID(string name, string signature) => Field(name, signature, true);

    public T GetStaticObjectField<T>(string name, string signature) where T : JObject, new() =>
        JNI.GetStaticObjectField<T>(this, GetStaticFieldID(name, signature));
    public T GetStaticField<T>(string name) => JNI.GetStaticField<T>(this, GetStaticFieldID(name, JNI.GetTypeSignature<T>()));
    public void SetStaticField<T>(string name, T value) => JNI.SetStaticField(this, GetStaticFieldID(name, JNI.GetTypeSignature<T>()), value);
    public T GetObjectField<T>(JObject instance, string name, string signature) where T : JObject, new() =>
        JNI.GetObjectField<T>(instance, GetFieldID(name, signature));
    public T GetField<T>(JObject instance, string name) => JNI.GetField<T>(instance, GetFieldID(name, JNI.GetTypeSignature<T>()));
    public void SetObjectField(JObject instance, string name, string signature, JObject value) => JNI.SetObjectField(instance, GetFieldID(name, signature), value);
    public void SetField<T>(JObject instance, string name, T value) => JNI.SetField(instance, GetFieldID(name, JNI.GetTypeSignature<T>()), value);

    public T CallStaticObjectMethod<T>(string name, string signature, params JValue[] args) where T : JObject, new() =>
        JNI.CallStaticObjectMethod<T>(this, GetStaticMethodID(name, signature), args);
    public T CallStaticMethod<T>(string name, string signature, params JValue[] args) =>
        JNI.CallStaticMethod<T>(this, GetStaticMethodID(name, signature), args);
    public void CallStaticVoidMethod(string name, string signature, params JValue[] args) =>
        JNI.CallStaticVoidMethod(this, GetStaticMethodID(name, signature), args);
    public T CallObjectMethod<T>(JObject instance, string name, string signature, params JValue[] args) where T : JObject, new() =>
        JNI.CallObjectMethod<T>(instance, GetMethodID(name, signature), args);
    public T CallMethod<T>(JObject instance, string name, string signature, params JValue[] args) =>
        JNI.CallMethod<T>(instance, GetMethodID(name, signature), args);
    public void CallVoidMethod(JObject instance, string name, string signature, params JValue[] args) =>
        JNI.CallVoidMethod(instance, GetMethodID(name, signature), args);
    public T NewObject<T>(string name, string signature, params JValue[] args) where T : JObject, new() =>
        JNI.NewObject<T>(this, GetMethodID(name, signature), args);
    public T NewObject<T>(string signature, params JValue[] args) where T : JObject, new() =>
        JNI.NewObject<T>(this, GetMethodID("<init>", signature), args);
}
#endif

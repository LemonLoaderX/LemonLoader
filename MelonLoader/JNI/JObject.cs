#if ANDROID
#nullable enable
using System;
using Java.Interop;

namespace MelonLoader.Java;

/// <summary>An owned or borrowed Java reference. Dispose owned references deterministically.</summary>
public class JObject : IDisposable
{
    private JniObjectReference reference;
    private bool ownsReference;
    private bool disposed;
    private int ownerThread;
    private int generation;
    private JNI.LocalFrameState? frame;

    /// <summary>The native handle. Local references may only be used on their creating thread.</summary>
    public IntPtr Handle
    {
        get { ValidateAccess(); return reference.Handle; }
        [Obsolete("Use JNI.Borrow or JNI.Adopt to state reference ownership explicitly.")]
        set
        {
            if (reference.IsValid || disposed) throw new InvalidOperationException("Cannot overwrite a JNI reference.");
            JNI.EnsureThread();
            JniEnvironment.References.CreatedReference(new JniObjectReference(value, JniObjectReferenceType.Local));
            SetReference(new JniObjectReference(value, JniObjectReferenceType.Local), true);
        }
    }

    public JNI.ReferenceType ReferenceType => reference.Type switch
    {
        JniObjectReferenceType.Global => JNI.ReferenceType.Global,
        JniObjectReferenceType.WeakGlobal => JNI.ReferenceType.WeakGlobal,
        _ => JNI.ReferenceType.Local
    };
    public bool IsDisposed => disposed;
    public bool IsNull => !reference.IsValid;
    public bool OwnsReference => ownsReference;

    public JObject() { }

    [Obsolete("Use JNI.Adopt or JNI.Borrow to state reference ownership explicitly.")]
    public JObject(IntPtr handle, JNI.ReferenceType type)
    {
        JNI.EnsureThread();
        var value = new JniObjectReference(handle, JNI.ToInteropType(type));
        if (type == JNI.ReferenceType.Local) JniEnvironment.References.CreatedReference(value);
        SetReference(value, true);
    }

    [Obsolete("This constructor transfers ownership. Use Transfer<T>() explicitly.")]
    public JObject(JObject source) { TakeFrom(source); }

    internal JniObjectReference Reference
    {
        get { ValidateAccess(); return reference; }
    }

    internal void SetReference(JniObjectReference value, bool owned)
    {
        if (reference.IsValid || disposed) throw new InvalidOperationException("Reference already assigned.");
        reference = value;
        ownsReference = owned;
        ownerThread = Environment.CurrentManagedThreadId;
        generation = JNI.ThreadGeneration;
        frame = value.Type == JniObjectReferenceType.Local ? JNI.CurrentFrame : null;
        if (frame != null && owned) frame.References.Add(this);
    }

    protected void TakeFrom(JObject source)
    {
        if (source == null) throw new ArgumentNullException(nameof(source));
        source.ValidateAccess();
        reference = source.reference;
        ownsReference = source.ownsReference;
        ownerThread = source.ownerThread;
        generation = source.generation;
        frame = source.frame;
        if (frame != null && ownsReference) frame.References.Add(this);
        source.reference = default;
        source.disposed = true;
        GC.SuppressFinalize(source);
    }

    public T Transfer<T>() where T : JObject, new()
    {
        T result = new();
        result.TakeFrom(this);
        if (this is JClass sourceClass && result is JClass resultClass) resultClass.Cache = sourceClass.Cache;
        return result;
    }

    public T ToGlobal<T>() where T : JObject, new() => JNI.NewGlobalRef<T>(this);
    public T ToLocal<T>() where T : JObject, new() => JNI.NewLocalRef<T>(this);

    internal void ValidateAccess()
    {
        if (disposed) throw new ObjectDisposedException(GetType().Name);
        if (reference.Type == JniObjectReferenceType.Local && reference.IsValid)
        {
            if (ownerThread != Environment.CurrentManagedThreadId)
                throw new InvalidOperationException("Local JNI references belong to their creating thread. Use ToGlobal across threads.");
            if (frame?.Active == false || generation != JNI.ThreadGeneration)
                throw new ObjectDisposedException(GetType().Name, "The JNI local frame or thread attachment has ended.");
        }
    }

    public bool Valid() => !disposed && reference.IsValid && frame?.Active != false &&
        (reference.Type != JniObjectReferenceType.Local || ownerThread == Environment.CurrentManagedThreadId && generation == JNI.ThreadGeneration);

    protected virtual void Dispose(bool disposing)
    {
        if (disposed) return;
        if (reference.Type == JniObjectReferenceType.Local && reference.IsValid)
        {
            if (!disposing) return;
            if (ownerThread != Environment.CurrentManagedThreadId)
                throw new InvalidOperationException("Dispose a local JNI reference on its creating thread.");
        }
        if (ownsReference && reference.IsValid && frame?.Active != false &&
            (reference.Type != JniObjectReferenceType.Local || generation == JNI.ThreadGeneration))
        {
            JNI.ReleaseReference(ref reference);
        }
        reference = default;
        disposed = true;
    }

    public void Dispose() { Dispose(true); GC.SuppressFinalize(this); }
    ~JObject() { try { Dispose(false); } catch { } }
}
#endif

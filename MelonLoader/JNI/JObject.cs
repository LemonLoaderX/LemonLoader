#if ANDROID
using System;

namespace MelonLoader.Java;

public class JObject : IDisposable
{
    private bool Disposed { get; set; }
    private readonly int ownerThreadId = Environment.CurrentManagedThreadId;

    public IntPtr Handle { get; set;}

    internal JNI.ReferenceType ReferenceType { get; set;}

    public JObject() { }

    public JObject(IntPtr handle, JNI.ReferenceType referenceType)
    {
        this.Handle = handle;
        this.ReferenceType = referenceType;
    }

    public JObject(JObject obj) : this(obj.Handle, obj.ReferenceType)
    {
        this.Disposed = obj.Disposed;
        ownerThreadId = obj.ownerThreadId;
        obj.Disposed = true;
        obj.Handle = IntPtr.Zero;
        GC.SuppressFinalize(obj);
    }

    protected virtual void Dispose(bool disposing)
    {
        if (Disposed || this.Handle == IntPtr.Zero)
            return;

        switch (this.ReferenceType)
        {
            case JNI.ReferenceType.Local:
                // Local references belong to the creating JNI thread/frame. The VM
                // releases abandoned locals when that frame exits; a CLR finalizer
                // must never attempt DeleteLocalRef from its own thread.
                if (!disposing)
                    break;
                if (ownerThreadId != Environment.CurrentManagedThreadId)
                    throw new InvalidOperationException(
                        "A local JNI reference must be disposed on its creating thread. Use a global reference across threads.");
                JNI.DeleteLocalRef(this);
                break;

            case JNI.ReferenceType.Global:
                JNI.DeleteGlobalRef(this);
                break;

            case JNI.ReferenceType.WeakGlobal:
                JNI.DeleteWeakGlobalRef(this);
                break;
        }

        Disposed = true;
        Handle = IntPtr.Zero;
    }

    public bool Valid()
    {
        return !Disposed && this.Handle != IntPtr.Zero;
    }

    ~JObject()
    {
        try { Dispose(disposing: false); }
        catch
        {
            // VM attachment or shutdown failure must not escape a CLR finalizer.
        }
    }

    public void Dispose()
    {
        Dispose(disposing: true);
        GC.SuppressFinalize(this);
    }
}
#endif

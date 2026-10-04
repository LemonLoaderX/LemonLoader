#if ANDROID
#nullable enable
using System;

namespace MelonLoader.Java;

/// <summary>A Java exception converted after clearing the pending JNI exception.</summary>
public class JThrowableException : Exception
{
    public JThrowable? Throwable { get; }
    public string JavaClassName { get; }
    public string JavaStackTrace { get; }

    public JThrowableException() : this(null, "java/lang/Throwable", "A Java operation failed.", "") { }
    public JThrowableException(JThrowable throwable) :
        this(throwable, "java/lang/Throwable", throwable.ToString(), "") { }
    internal JThrowableException(JThrowable? throwable, string className, string message, string stack) : base(message)
    { Throwable = throwable; JavaClassName = className.Replace('/', '.'); JavaStackTrace = stack; }
    public override string ToString() => base.ToString() +
        (JavaStackTrace.Length == 0 ? "" : Environment.NewLine + "Java stack:" + Environment.NewLine + JavaStackTrace);
}
#endif

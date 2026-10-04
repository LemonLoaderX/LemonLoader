# Java access for Mods

Android Mods target net10.0 and reference the Android MelonLoader.dll.
The product runs on .NET 11; the historical loader/net6 installation folder is
a file-layout name, not the current compiler target. Existing compiled net6 Mods
can load on this runtime, subject to the JNI behavior changes below.

Use MelonLoader.Java. Loader initializes the JavaVM and app ClassLoader before
Mods start. Mods must not create or destroy a VM, replace Loader's runtime, or ship
a separate Java.Interop DLL. Loader supplies its pinned Java.Interop implementation.

## Calls

Classes use slash-separated JNI names. Object descriptors use Lname; and arrays
use [element. Method descriptors contain argument types followed by return type.
Resolve member IDs once when making repeated calls. JClass shares synchronized
instance/static caches across FindClass results; failed lookups are not cached.

```csharp
using MelonLoader.Java;

using var integer = JNI.FindClass("java/lang/Integer");
using var text = JNI.NewString("42");
int value = integer.CallStaticMethod<int>(
    "parseInt", "(Ljava/lang/String;)I", text);
```

Primitive types are bool, sbyte, char, short, int, long, float and double.
Java byte is signed; convert byte spans with MemoryMarshal.Cast<byte, sbyte>.
JValue accepts these primitives, a JObject, IntPtr or null; unsupported boxed
values throw. Null JObject arguments represent Java null. JNI cannot infer every
argument type from jvalue bits: argument order and types must match the descriptor.
Counts, return/access kind and descriptor syntax are checked before native calls.

Use ReadOnlySpan<JValue> overloads to avoid argument-array allocations:

```csharp
var parse = integer.GetStaticMethodID("parseInt", "(Ljava/lang/String;)I");
Span<JValue> arguments = stackalloc JValue[] { new(text) };
int parsed = JNI.CallStaticMethod<int>(integer, parse, arguments);
```

## References

- JObject and its subclasses own their reference unless created through Borrow.
  Use using/Dispose. Ordinary object-returning calls create global references so
  the result can outlive a call and be passed between threads.
- FindClass returns an owned local reference to a process-cached class. Dispose
  on the creating thread. Its member IDs remain valid while the cached class lives.
- NewStringLocal, NewObjectLocal and CallObjectMethodLocal return locals for short
  same-thread work. Use LocalFrame for batches; ending it invalidates its locals.
  Promote with ToGlobal<T>() before a local frame or thread attachment ends.
- Borrow<T>(handle, kind) does not delete the caller's reference. Adopt<T> owns it:
  the original owner must stop using/deleting that handle. Borrowed references still
  obey the caller's lifetime, JNI thread/frame rules, and object type.
- Transfer<T>() moves ownership and invalidates the source. ToLocal/ToGlobal copy
  the reference. DeleteLocalRef/DeleteGlobalRef also dispose/invalidate the wrapper.
  Raw handle mutation and ownership-transferring constructors are obsolete.

```csharp
using var thread = JNI.AttachCurrentThread();
using var frame = JNI.LocalFrame();
using var temporary = JNI.NewStringLocal("temporary");
using var persistent = temporary.ToGlobal<JString>();
```

Dispose frames before thread scopes, in reverse order. Scope objects stay on their
creating thread; never hold them across await. Put the whole synchronous JNI block
inside Task.Run if needed. Thread scopes detach only threads attached by Loader.
Globals can cross threads; concurrent use and disposal still require caller
synchronization. Weak globals require promotion to a strong local/global before
use because Java GC can clear them.

## Errors and arrays

Ordinary failed Java operations immediately throw JThrowableException and clear
pending JNI state. JavaClassName, Message and JavaStackTrace retain Java details.
Catch this exception around the operation rather than testing an invalid result
or relying on a later CheckExceptionAndThrow. A successful Java null is distinct
from an exception; test result.IsNull when the method may return null.

ExceptionCheck/Clear/Describe and Throw/ThrowNew are low-level escape hatches.
Throw leaves a pending exception; clear it or return to a real Java native caller
before performing unrelated JNI operations. ExceptionOccurred returns an owned
local Throwable without promoting it while the exception is pending.

Primitive array region APIs accept spans and check managed buffer/destination
bounds. GetArrayElements returns a managed copy; it never retains a Java pin.
Object-array iteration returns owned objects that each require disposal.

## Migration

Common JNI/JClass/JObject/JString names and params-array overloads remain.
Behavior changes intentionally reject invalid IDs, access modes, signatures,
unsupported arguments, wrong-thread locals and overwritten live handles.
Do not depend on a copy constructor behaving like reference duplication.
Mods using the removed JNIEnv/JavaVM table structs must migrate and rebuild.
Raw class definition, reflected-member conversion,
native registration, direct buffers and unimplemented raw facilities are outside
this facade; thread/local scopes replace the old unimplemented frame placeholders.
The native runtime's crypto helpers use their own hosting and are unaffected.

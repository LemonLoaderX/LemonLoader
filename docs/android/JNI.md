# Java access for Android Mods

New Android Mods target net10.0 and reference MelonLoader.dll and its pinned
Java.Interop.dll with Copy Local disabled. Loader runs on .NET 11. The historical
loader/net6 directory remains an installation path, not the compilation target.

## Standard Java model

Use Java.Interop JavaObject/IJavaPeerable, JavaException and Java primitive/object
arrays. Loader hosts the existing ART VM and app ClassLoader. Mods must not create
or destroy a VM, replace JniRuntime, or ship another Java.Interop copy.
MelonLoader.Android supplies typed binding, common Android peers and callbacks.

```csharp
using MelonLoader.Android;

static readonly Func<string, int> ParseInt =
    JavaBinding.BindStatic<Func<string, int>>("java/lang/Integer", "parseInt");

int value = ParseInt("42");
```

Bind once. Binding resolves the member immediately and caches the compiled delegate
and Java.Interop member metadata. Delegate parameters/return types produce the JNI
descriptor; strings, arrays and peers use upstream value marshalers. Instance
delegates put an IJavaPeerable receiver first. Calls check the actual Java receiver
class before invoking JNI. Constructors return a peer compatible with the selected
Java class; incompatible return types fail at binding.

```csharp
using Java.Interop;

[JniTypeSignature("java/lang/StringBuilder", GenerateJavaPeer = false)]
public sealed class StringBuilderPeer : JavaObject
{
    private static readonly JniPeerMembers Members =
        new("java/lang/StringBuilder", typeof(StringBuilderPeer));
    public override JniPeerMembers JniPeerMembers => Members;
    public StringBuilderPeer(ref JniObjectReference reference,
        JniObjectReferenceOptions options) : base(ref reference, options) { }
}

var create = JavaBinding.BindConstructor<Func<string, StringBuilderPeer>>(
    "java/lang/StringBuilder");
var append = JavaBinding.BindInstance<
    Func<StringBuilderPeer, string, StringBuilderPeer>>(
    "java/lang/StringBuilder", "append");
var text = JavaBinding.BindInstance<Func<StringBuilderPeer, string>>(
    "java/lang/StringBuilder", "toString");

using var builder = create("Hello");
using var result = append(builder, " Java");
string message = text(result);
```

Signatures use the declared delegate types, so overloads remain deterministic.
Java Object[] and String[] are distinct; use JavaObjectArray<JavaObject> for
Object[]. Java byte maps to sbyte. Types without a JniTypeSignature or upstream
mapping fail during binding. Calls through six arguments use typed stack-based
marshaling; larger delegates use a boxed argument buffer. Generated or unusual
bindings can use JniPeerMembers directly.

GetStaticField<T> infers its field type. For other field access, explicit overload
descriptors, nonvirtual dispatch or native registration use the standard
JniPeerMembers/JniEnvironment interface within a thread scope. Do not duplicate
their metadata, reference structs or ownership rules in Mods.

## Lifetime and threads

Returned peers own global references and implement IDisposable. Use using.
Separate results are independently owned; Java null becomes C# null. Strings and
managed-array results are converted and their temporary references released.
JavaArray types remain Java-owned storage; CopyFrom/CopyTo perform bounded copies.

Typed binding operations establish a thread scope automatically. For repeated
work, surround the block with AndroidJava.AttachCurrentThread(); nested calls reuse
the attachment. Direct Java.Interop operations require this outer scope. Dispose
peer wrappers before ending it. End scopes in reverse order on their creating
thread, without crossing await. Do not dispose copied scopes; stale copies and
out-of-order disposal throw before altering attachment state. Put synchronous JNI
work inside Task.Run when needed.
Globals can cross threads; synchronize concurrent access/disposal yourself.

Loader maintains weak managed-peer registry entries and releases abandoned peers
on the CLR finalizer thread. Deterministic disposal is still preferable. Raw local
references obey JNI same-thread/frame lifetime and should be managed with upstream
JniObjectReferenceOptions; never retain locals across Java callbacks or detach.

## Android and UI callbacks

UnityPlayer.CurrentActivity returns an owned current AndroidActivity peer; reacquire
it after Activity recreation. Activity.Assets provides AndroidAssetManager and typed
InputStream access. APKAssetManager adapts assets into .NET streams with a reusable,
bounded Java byte buffer and IOException semantics.

```csharp
await AndroidThread.RunAsync(() =>
{
    using var activity = UnityPlayer.CurrentActivity;
    // Use Android peers here on the UI thread.
}, cancellationToken);
```

RunAsync observes managed callback exceptions through its Task. Cancellation
releases queued registrations; it does not interrupt an already running action.
An Activity that never executes queued work needs caller cancellation/timeout.

JavaCallbacks.Create<TPeer> implements Java interfaces through an embedded helper
and java.lang.reflect.Proxy. TPeer uses a JniTypeSignature for that interface.
JavaCallbackMethod supplies the Java method name and a typed delegate, including
overloads. All abstract methods must be supplied. Object identity methods are
handled by the proxy; default methods need explicit handlers if invoked.

```csharp
using var runnable = JavaCallbacks.Create<JavaRunnable>(
    new JavaCallbackMethod("run", (Action)(() => Console.WriteLine("Java called C#"))));
runnable.Peer.Run();
```

Keep the registration alive while Java uses its proxy, then dispose it. Callback
argument peers are borrowed for the invocation and disposed afterward, including
elements of managed object arrays and nested arrays. These are independent wrappers;
cleanup preserves caller-owned peers. Create an independent peer/reference if storing
them. Object arguments retain runtime type conversion; nested arrays use the same
scoped ownership, with a 64-level limit on recursive managed-array conversion.
Java array peer wrappers keep Java-owned storage, including cyclic arrays.
Elements obtained yourself through JavaObjectArray follow upstream GetValue
ownership rules. Returned primitive/string/array values
are boxed/marshaled for Java. Callback exceptions become Java RuntimeException;
no managed exception escapes the native entry point. A disposed Runnable is a
no-op; other disposed interface calls throw.

The callback DEX is embedded in MelonLoader.dll and loaded lazily with
InMemoryDexClassLoader (API 26+), using the app ClassLoader as parent. APK injection
needs no extra DEX entry. CoreCLR crypto keeps its separate private classloader.

## Exceptions and migration

Catch Java.Interop.JavaException. Message, InnerException and JavaStackTrace keep
Java diagnostics. The pending exception is cleared before throwing to C#.
Dispose a caught JavaException when done with its retained Throwable peer.

This new version removes MelonLoader.Java JNI/JObject/JClass/JValue/member-ID
interfaces and their compatibility shims. Mods that used them must migrate/rebuild.
Mods unrelated to JNI may still load, but compatibility with the old JNI API is
not a product requirement. Android hosting and desktop compilation remain separate.

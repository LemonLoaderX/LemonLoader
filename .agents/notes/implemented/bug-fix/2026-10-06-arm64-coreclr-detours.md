# Agent Note: ARM64 CoreCLR method detours

Status: implemented

## Problem

MonoMod 22 recognizes older ARM64 precodes with embedded data. Modern CoreCLR
stores the target and MethodDesc in a separate data page. Patching the executable
precode can leave already compiled direct and reflection calls on the original
body. Harmony's patch inventory does not detect this failure.

The Android runtime fallback also has no JIT notifications. Even after selecting
the correct body, tiered compilation can replace it and bypass the patch.

## Decision

The MonoMod.Common source fork recognizes complete ARM64 page-precode templates,
checks the owning MethodDesc, and resolves their target slots. It does not follow
arbitrary literal branches or unwrap PInvoke/interpreter/return-buffer adapters.
Unprepared FixupPrecode triggers one preparation retry; an unchanged target fails
with a managed exception rather than an unbounded retry or a prestub overwrite.

The known .NET 11 ARM64 JIT GUID selects a dedicated runtime platform. It forwards
the native compilation request unchanged and reads only its MethodDesc identity
to notify detours of recompilation for pinned methods. It does not reconstruct
private RuntimeAssembly structures or parse legacy generic-signature layouts.
Callbacks preserve the thread's last P/Invoke error, isolate failing observers,
and contain diagnostic-writer exceptions. The method index reconciles the live
pin count under its lock after preparation, which may enter the JIT, so a final
concurrent Unpin cannot publish a stale record. Delegate thunks and error helpers
are warmed before installing the JIT hook to avoid recursive compilation of
those helpers.

The vtable is data: Unix writes request RW permissions, avoiding Android's refusal
to add executable permission to a file-backed RELRO page. The compiler's native
exceptions use MonoMod upstream's ARM64 POSIX exception helper around both
transitions. The inner native wrapper saves the unwind exception before returning
to managed code; the outer wrapper rethrows after managed cleanup. Notifications
are skipped for failed compilation, and nested callbacks preserve the pending
exception slot. Loader builds the helper with its pinned NDK and embeds it in
RuntimeDetour; a unique private runtime file is unlinked immediately after load.
No installed SO input or separate deployment policy is added. Missing build input
rejects hook installation; failed installation releases its unpublished resources.

Modern Unix JIT discovery resolves libclrjit alongside CoreLib, avoiding
Process.Modules during embedded runtime initialization. Loader initializes the
runtime singleton before installing Harmony patches; replacing it can leave the
existing static subscription attached to the previous platform. The factory roots
and reuses the installed .NET 11 hook owner for the process; native function
pointers do not root managed delegates. Unknown JIT GUIDs
retain the existing fallback and do not opt into this layout.

## Alternatives considered

- Patching only the public precode is simpler, but direct calls can bypass it.
- Generic literal-branch walking avoids runtime structures, but can unwrap
  installed detours and argument adapters. Full template and ownership checks
  limit the supported interpretation.
- The historical MethodDesc + 8 approach is compact, but modern MethodDesc base
  sizes depend on classification and optional slots.
- Disabling tiered compilation avoids some body replacements, but does not fix
  the wrong entrypoint and removes runtime optimization globally.
- Reusing .NET 6 JIT helpers would reduce source changes, but .NET 11 changes
  signature layouts and private reflection implementation. Pinned method identity
  already supplies the information detours need.
- PortableEntryPoint is a data-only WASM contract in the pinned runtime, not the
  Android ARM64 precode contract.
- Forwarding the native compiler directly through a managed delegate is smaller,
  but POSIX unwinding can terminate the process when the EE throws for a missing
  method. A C# catch cannot handle that boundary. Upstream's native helper retains
  the CLR's original exception instead of translating every failure to invalid IL.

## Consequences

The adaptation stays in the maintained source fork; Loader keeps the existing
factory interface. No binary rewriting, global tiering override, runtime-export
addition or Mod interface change is required. The JIT hook adds a pinned-method
lookup after successful compilation and remains installed for the process lifetime.
The embedded native helper adds a bounded per-process load and two small entry
stubs, with thread-local exception storage owned by upstream's implementation.
Concurrent mutation/execution of a native patch is still governed by MonoMod's
existing limitations; this does not establish general concurrent patch safety.

Host fixtures verify template recognition, page offsets, ownership, adapter
rejection, pin-publication races and callback failure containment. Their synthetic
compiler uses one hook owner and does not write .NET 11 MethodDesc flags on the
.NET 10 host. The Android smoke Mod verifies prefix/postfix with original
execution, direct/reflection/pre-existing delegate calls, workers, delayed hot
calls, repeated factory selection and two rounds of unpatch/repatch. Host x64
fallback tests do not substitute for these Android assertions. Device/build
evidence belongs in ignored Output.
The smoke also compiles invalid IL and a synthetic reference to a missing method;
both must remain ordinary managed errors. A fallback platform cannot satisfy the
ARM64 smoke verdict merely by passing calls before tiering replaces their bodies.

The source-resolution policy in
[independent source resolution](../process/2026-10-02-independent-source-resolution.md)
remains applicable; fork synchronization alone does not update a consumer pin.

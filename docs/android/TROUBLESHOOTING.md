# Android troubleshooting

Start from a fresh reproduction. Preserve the input versions, timestamps,
release and runtime manifests, logcat, `Latest.log`, and the observable
application result. A successful command or living PID is not sufficient.

## Bootstrap does not start

Confirm that the APK contains `lib/arm64-v8a/libmain.so`, that Unity loads the
library named `main`, and that the library exports `JNI_OnLoad`. Verify AArch64,
Android imports, and ELF alignment with
`scripts/build/verify-android-bootstrap.ps1`.

`JNI_OnLoad` registers methods only. Managed startup occurs after Unity's native
loader and `il2cpp_init`; missing early managed logs do not by themselves prove
that JNI registration failed.

## CoreCLR initialization fails

Check the extracted `runtime-identity.json`, the engine hash, and the actual
mapped `libcoreclr.so`. The runtime must export `coreclr_initialize`,
`coreclr_create_delegate`, and `coreclr_shutdown` without a MonoVM identity.

`[CoreCLR.Android.Host]` reports the first failing PAL or host stage.
`[CoreCLR.Android.Thread]` reports a bounded native thread-resource snapshot.
Investigate `EAGAIN` as a thread/PID limit or leak and `ENOMEM` as native address
space or stack pressure. `EPERM` or `EACCES` from affinity calls can indicate a
restricted Android kernel; the maintained runtime preserves the inherited valid
mask for those two errors.

## Managed cryptography fails

The Patcher must promote the runtime artifact's helper DEX into the application
class loader. The payload must contain
`libSystem.Security.Cryptography.Native.Android.so` and must not substitute a
generic Linux OpenSSL shim.

If the helper class is missing, verify that the Patcher selected the next unused
top-level `classesN.dex` entry. If JNI state is missing, check that the bootstrap
and CoreCLR resolve the same native cryptography module rather than loading a
second namespace-local copy.

## Il2CppInterop startup or injection fails

Confirm that Interop generation consumed the target `libil2cpp.so`, selected the
correct Unity version, and used the revision recorded in
`interop-manifest.json`. Android must use the ARM64 resolver and the hook matching
the target's actual generic-method lookup signature; it must not use the desktop
x86 scanner.

For value-type corruption, inspect AAPCS64 classification, homogeneous
aggregates, indirect returns, and local initialization in restored methods. A
managed exception may be the first visible consequence of an earlier native ABI
mismatch.

## Native hook fails or crashes nearby code

Dobby is configured to require a near relay for short ARM64 targets. Allocation
failure must return an error and leave the target instructions unchanged. Do not
fall back to a larger overwrite that can cross into an adjacent function.

Verify that the target address belongs to an executable `libil2cpp.so` segment,
the selected Unity resolver matches the version family, and the returned
trampoline is not published after a failed hook.

An x86_64 Android emulator may run an ARM64 application through a native bridge.
Such bridges can expose guest ARM code as readable, non-executable mappings and
reserve the nearby guest address space with anonymous `PROT_NONE` mappings. The
maintained Dobby fork uses one of those reservations only for a translated-code
target. Run the fork's `scripts/test-android-near-hook.ps1` against the emulator
to distinguish this layout from a method-resolution failure.

## APK resources disappear

Do not fully extract and recompress an APK in a case-insensitive Windows
directory. ZIP entries that differ only by case can overwrite each other. Use
LemonLoader.Patcher's ZIP pipeline and check for duplicate entries before any
output is published.

## Old Mods or configuration remain

Replacement installation does not imply that application-owned files were
replaced. Inspect the packaged deployment profile, per-file policy, installed
ownership state, and the actual device file. Unknown and user-owned files are
preserved intentionally.

## Reporting evidence

Remove package identities, game assets, account information, device serials,
local paths, signing material, and credentials before sharing evidence. Prefer a
synthetic regression that reaches the same framework boundary.

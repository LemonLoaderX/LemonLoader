# Java.Interop source build

Loader pins dotnet/android's Java.Interop subtree in eng/AndroidDependencies.props.
Setup uses the ordinary independent source resolver and sparse checkout. Build
never fetches or changes an existing source revision. Pass JavaInteropSourceRoot
to product build scripts for an explicit checkout.

This project compiles upstream managed files and runs its JNI environment
generator. It targets net10.0, uses direct function-table calls, and produces no
native shim or helper JAR/DEX. Loader hosts an externally owned JavaVM and disables
upstream generated-managed-subclass registration. Loader supplies a weak peer
registry, finalizer/thread hosting and standard JavaException conversion.
Release builds suppress debug data and stage the upstream MIT license.

The Android workload build and peer generators are unnecessary for this hosting
model. No upstream source or binary is rewritten by this build. Mods reference
this single product-supplied Java.Interop assembly and use its standard peer model;
MelonLoader.Android adds typed calls, platform peers and an independent embedded
callback helper. See [Java access](../../docs/android/JNI.md).

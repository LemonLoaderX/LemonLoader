# Runtime troubleshooting

This guide retains useful findings from the earlier Android/Bionic experiments,
not their local build/device timeline. Current commands and source selection are
in [runtime development](RUNTIME-DEVELOPMENT.md); qualification procedures are in
[testing](TESTING.md) and [embedded crypto acceptance](../maintenance/embedded-crypto-acceptance.md).

## Build and packaging

| Symptom | Cause and response |
| --- | --- |
| NU1102 for the pinned compiler/toolset with only nuget.org listed | External artifacts change implicit NuGet.config discovery. The builder passes the source RestoreConfigFile explicitly. Do not downgrade tool versions. |
| NU5118 duplicate CoreLib PDB entries | Older source packaging can include the same managed symbols twice. The maintained build requests DebugType=None and DebugSymbols=false; inspect new packages after upstream updates rather than suppressing duplicate validation. |
| Bionic Mono bundle fails NETSDK1004 in a CoreCLR-only build | The baseline's Bundle.bundleproj selects Mono for Bionic independently of PrimaryRuntimeFlavor. The builder uses _BuildBundle=false while retaining CoreCLR pack validation. Review this internal property on upstream updates. |
| Missing libnethost.so during packs.product | The source subset needs host.native; the maintained builder includes it. Do not copy another target's output to complete a package. |
| FORCE_ANDROID_OPENSSL cannot find headers | Bionic's OpenSSL shim needs desktop build headers, not deployable desktop libraries. Supply OPENSSL_INCLUDE_DIR explicitly; device crypto libraries are a separate input. |
| Slow preflight Git status through DrvFS | Linux and Windows Git stat/index metadata differ. The builder uses git.exe through WSL interop when available, preserving source checks. |
| Reusing relocated CMake caches fails with old absolute paths | Keep prior outputs/evidence, then select a new output root and rebuild. Do not rewrite an old cache to appear relocatable. |

If system OpenSSL headers are unavailable, an isolated WSL header cache can be
prepared without installing packages system-wide:

```bash
mkdir -p ~/.cache/lemonloader/openssl-build-headers
cd ~/.cache/lemonloader/openssl-build-headers
apt-get download libssl-dev
dpkg-deb -x libssl-dev_*.deb extracted
cp extracted/usr/include/x86_64-linux-gnu/openssl/*conf*.h extracted/usr/include/openssl/
```

Use a new directory containing only one selected deb and record its version/hash
locally. These are compilation headers. Never ship Ubuntu x64 libraries to Android.
Failed logs, nupkgs and symbol files remain private inputs/evidence, not releases.
The focused native nupkg inspector is retained under Loader because it checks
all native files, including glibc imports, without staging a product:

```bash
bash scripts/test/inspect-runtime-native.sh "<runtime.nupkg>" android-arm64
```

Run under Linux/WSL with unzip and a Linux NDK; ANDROID_NDK_ROOT overrides the
default tool cache. Native inspection follows structural/hash validation and
does not authenticate a package or prove dependency availability/API execution.

## Bionic Startup

A managed/native feature mismatch can branch to a missing QCall during early
CoreCLR startup. One baseline enabled FeatureXplatEventSource for TargetOS=linux
(including Bionic), while native clrfeatures.cmake excluded Android. JIT mappings
identified XplatEventLogger.EventSource_GetClrConfig as the caller. The source
builder disables FeatureXplatEventSource for Bionic to align both sides; it does
not disable EventPipe or change HTTP behavior. Recheck this condition on rebase.

Changing dlopen from RTLD_LOCAL to RTLD_GLOBAL did not solve that mismatch. A
null target or JIT doublemapper PC is not evidence of OpenSSL/affinity failure.
Keep the matching report, native symbols and, where available, PerfMap/JIT dump
records to resolve managed frames. Do not add global symbol loading as a default
workaround. See [native crash evidence](HARDENING.md) for retained report limits.

## Crypto and Network

- Bionic's OpenSSL shim cannot use Android system BoringSSL as a drop-in provider.
  Missing a2d_ASN1_OBJECT is one failure mode. Supply reviewed Android ARM64
  OpenSSL libraries with source/license identity; never substitute desktop SOs.
- A crypto known-answer test does not establish TLS trust. PartialChain without
  a CA directory is a trust-store configuration failure, not a reason to disable
  certificate validation. Conscrypt/system CA availability varies by Android
  version and application linker namespace; app-context negative TLS cases matter.
- Android retains official synchronous HttpClient.Send rejection. Bionic's
  synchronous behavior differs; no compatibility patch should erase that boundary.
- A bare adb-shell native host does not provide a JavaVM or crypto helper
  ClassLoader. Test Android JNI crypto in a Java-hosted application context.
- Shell reflection/emit/thread/GC tests, loopback HTTP and a positive HTTPS request
  do not qualify Unity, Harmony, IL2CPP ABI, client certificates, cancellation,
  long sessions, API 26 or physical 16 KiB-page devices.

The historical shell CoreClrProbe, runner and fixed-version OpenSSL downloader
are retired; they are not current build inputs or an authenticated OpenSSL build
workflow. Product smoke/device acceptance
requires explicit application/device selection and never implies uninstalling,
data clearing or signing changes.

## Dependency Adaptations

.NET 11 replaces the old IRuntimeMethodInfo.get_Value path with static GetValue;
the maintained MonoMod.Common fork supports the relevant shapes. Keep that fix
in source with its probe, not patched DLLs. CPU-present-count discovery, Android
affinity EPERM/EACCES handling and older NULL-handle checks already existed in the
reviewed upstream baseline. Inspect source before replaying legacy fixes; optional
resource-snapshot/initialization-stage diagnostics are not proof of missing
functional behavior. Runtime and deployment digests from old experiment recipes
are not current layout-9 startup requirements.

# Agent Note: Embedded Android crypto helpers

Status: implemented

## Problem

CoreCLR Android needs Java helper classes. Promoting a helper DEX to classesN.dex
couples injection to game code layout. An isolated Java System.load experiment
created two crypto module identities: CoreCLR used the copy without JNI state.

## Decision

Embed the validated pack's complete helper DEX in libmain.so. Android creates an
InMemoryDexClassLoader with boot-loader parent; helpers depend only on platform
classes and game classes cannot shadow them. Read-only ELF bytes and retained JNI
references live for the process. AndroidCryptoNative_InitWithClassLoader receives
JavaVM/loader explicitly; every crypto P/Invoke resolves through that initialized
dlopen module. Do not call System.load or mutate ART private ClassLoader fields.

Release metadata declares embedded mode; build/staging verifies the explicit
runtime export, matching crypto inputs and full DEX bytes after stripping.
Runtime packs contain DEX as a verified build input; Loader archives contain SOs
without standalone helper DEX. Only the Android profile embeds helpers; Bionic
uses private OpenSSL and separate trust-store qualification.

The original transition kept frozen pre-26 and layout-8/external-DEX inputs for
recovery. That compatibility choice is superseded by [CoreCLR 10 retirement](../simplification/2026-10-03-retire-coreclr10-workflows.md)
and [reader retirement](../simplification/2026-10-03-retire-layout8-readers.md).
Current producers use the [minimal payload](../simplification/2026-10-02-minimal-produced-payload.md).

## Alternatives considered

- Top-level DEX is verified and uses the app ClassLoader but retains game-layout
  coupling. Merging into game DEX adds rewriting, collision and method-limit work.
- File-based DexClassLoader preserves API24/25 but adds extraction and writable
  code lifecycle. Product support intentionally starts at API26.
- Bionic/OpenSSL eliminates Java helpers but changes trust semantics and adds
  private OpenSSL maintenance. It remains a separate selectable profile.

## Consequences

The runtime fork must be rebuilt with its explicit host API; old shims cannot
substitute for it. Publish reviewed runtime inputs before consumers. Development
packs retain their real source identity and never become formal packs by relabeling.
[Runtime development](../../../../docs/android/RUNTIME-DEVELOPMENT.md) owns commands.

Host tests cover constructor/JNI failures, retained lifetime, no System.load and
exact P/Invoke module reuse. Constructor lookup errors must clear the exception
and release the local class before any module/buffer is created. Native directory
staging selects SOs, avoiding upstream raw DEX leakage without a filename blacklist.
APK/directory tests preserve game DEX/smali and reject incomplete/mixed inputs.

Host mocks cannot prove ART or TLS. Initialization is serialized and inherits
upstream fatal checks for incompatible Java signatures; it is not a general
concurrent interface. Device coverage and symbols are separate acceptance inputs.
Client-certificate acceptance checks the negotiated key/certificate and server
response; mutual-authentication state alone does not prove server acceptance.
Native-instance evidence uses the actual process maps and exact ELF inputs without
loading an extra copy for inspection. These checks and endpoint limitations belong
to the [device procedure](../../../../docs/maintenance/embedded-crypto-acceptance.md).

## Prior-note Audit

The retired porting overview's unique native-instance failure is retained in
Problem; its startup/ownership details remain in Architecture/Runtime. Source
independence is owned by the [source decision](../process/2026-10-02-independent-source-resolution.md).
Crash reporting is separate. The private Interop-free proposal remains unimplemented
and is not implied by embedding or installation simplification.

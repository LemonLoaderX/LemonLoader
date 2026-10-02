# Embedded crypto device acceptance

Status: pending maintainer acceptance. Host/NDK checks do not satisfy this gate.

## Inputs and identity

- Use the matching rebuilt Android runtime pack, Loader archive and Patcher
  output identified by exact source revisions and artifact SHA-256. Do not mix
  the old crypto SO with the new bootstrap.
- Retain the original/private test APK, existing signer and successful rollback
  artifact privately. Device installation and signing are maintainer operations;
  this checklist does not authorize uninstalling or clearing application data.
- Verify the final APK with Patcher's `scripts/verify-apk-layout.ps1`. Confirm
  `coreClrCryptoDexMode: embedded`, API declaration at least 26, and matching
  `coreClrCryptoBootstrapSha256`. Original game DEX entries should be unchanged
  and no additional helper `classesN.dex` should appear.
- Keep exact-build native symbols and local build logs outside release archives.
  Record device API, ABI and page size privately with the test evidence.

## Matrix

Test API 26 and a current Android version where available. A successful current
device does not prove API 26. Include a 16 KiB device in broader qualification;
an aligned ELF alone does not prove that hardware target. Bionic gets separate
smoke coverage and must remain without Android helpers.

## Required checks

1. Cold process startup: Loader reaches managed startup and normal scene/frame
   callbacks; no missing helper, JNI exception or library initialization error.
2. Repeat process launches and Activity recreation: no ClassLoader/module
   reinitialization, stale JNI references or unexpected DEX extraction.
3. Known-answer tests through .NET APIs: SHA-256, HMAC, AES encrypt/decrypt,
   PBKDF2 including empty and arbitrary-byte passwords, RSA sign/verify and RNG
   basic operation. Compare against established vectors, not generated values.
4. Background managed thread crypto: worker attachment, helper calls and return
   to the application remain valid; no reliance on the caller's FindClass context.
5. Asynchronous HTTPS and SslStream: valid certificate succeeds, invalid chain
   and hostname are rejected by default, and managed callback behavior does not
   bypass platform trust rejection. Do not test success using permissive callbacks.
6. Client-certificate handshake against a controlled endpoint, covering
   DotnetX509KeyManager rather than only server authentication.
7. Existing platform trust/network-security-config behavior is preserved.
   Endpoint names, certificates and credentials are private test inputs.
8. Native module identity: instrument privately or inspect maps to confirm the
   module initialized with the helper loader is the P/Invoke module, not a second
   namespace-local copy. A library filename alone is not proof of identity.
9. Existing Mods/Harmony/Interop and a longer session work at least as well as
   the saved baseline; record pre-existing warnings separately from regressions.
10. Negative package tests reject missing/wrong crypto SO, wrong bootstrap digest,
    mixed modes and damaged embedded bytes without accepting a broken pack.

## Evidence and limitations

Keep build identities, APK layout verification, known-answer results, startup
and TLS errors, selected native module evidence and rollback notes together in
ignored local output. Include the whole session context, not only a success line.

API 26 ART in-memory DEX compatibility, native TLS/provider behavior and actual
game acceptance remain unqualified until this matrix runs. Android profile's
upstream synchronous HTTP restriction remains unchanged. The planned crash
collector is not yet implemented; capture existing logs/logcat during maintainer
acceptance where possible and do not mistake their absence for a clean run.

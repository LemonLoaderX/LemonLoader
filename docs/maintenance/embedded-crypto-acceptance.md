# Embedded crypto device acceptance

Host/NDK checks do not replace this device-acceptance procedure.

## Inputs and identity

- Use the matching rebuilt Android runtime pack, Loader archive and Patcher
  output identified by exact source revisions and artifact SHA-256. Do not mix
  the old crypto SO with the new bootstrap.
- Retain the original/private test APK, existing signer and successful rollback
  artifact privately. Device installation and signing are maintainer operations;
  this checklist does not authorize uninstalling or clearing application data.
- Verify the final APK with the [Patcher verifier](https://github.com/LemonLoaderX/LemonLoader.Patcher/blob/main/scripts/verify-apk-layout.ps1). Confirm
  embedded mode and API 26+ in the Release manifest, and validate its bootstrap
  through the Release file hashes. Layout-9 APK configuration has no bootstrap
  digest or crypto-mode fields. Original game DEX entries should be unchanged
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
   reinitialization, stale JNI references or unexpected DEX extraction. Confirm
   the PID stays the same, the old Activity is destroyed and the new object is
   distinct. Reacquire CurrentActivity and exercise UI callbacks, APK assets and
   worker-thread crypto after each recreation. A private secondary Activity can
   isolate reference/lifetime behavior when a game's Unity Activity exits its
   process; record any fixture-controlled currentActivity assignment. That result
   does not qualify recreation of the game's Unity Activity or its lifecycle.
3. Known-answer tests through .NET APIs: SHA-256, HMAC, AES encrypt/decrypt,
   PBKDF2 including empty and arbitrary-byte passwords, RSA sign/verify and RNG
   basic operation. Compare against established vectors, not generated values.
4. Background managed thread crypto: worker attachment, helper calls and return
   to the application remain valid; no reliance on the caller's FindClass context.
5. Asynchronous HTTPS and SslStream: valid certificate succeeds, invalid chain
   and hostname are rejected by default, and managed callback behavior does not
   bypass platform trust rejection. Do not test success using permissive callbacks.
6. Client-certificate handshake against a controlled endpoint, covering
   DotnetX509KeyManager rather than only server authentication. Include correct,
   missing and unrelated client certificates through HttpClient and SslStream.
   Require a successful application response and the expected negotiated local
   certificate for the positive SslStream case; mutual authentication alone can
   still accompany a server rejection. Treat unrelated TLS/network exceptions as
   inconclusive, not successful negative cases. Distinguish certificate-container
   import failures from handshake failures; do not enable obsolete algorithms just
   to import a fixture. A re-export must preserve the certificate and private key.
7. Existing platform trust/network-security-config behavior is preserved.
   Endpoint names, certificates and credentials are private test inputs.
8. Native module identity: instrument privately or inspect maps to confirm the
   module initialized with the helper loader is the P/Invoke module, not a second
   namespace-local copy. A library filename alone is not proof of identity. Match
   exact native-file hashes and ELF load-segment offsets to same-process maps,
   checking load instances before and after the operation. Do not load another
   module merely to inspect its identity.
9. Existing Mods/Harmony/Interop and a longer session work at least as well as
   the saved baseline; record pre-existing warnings separately from regressions.
10. Negative package tests reject missing/wrong crypto SO, wrong bootstrap digest,
    mixed modes and damaged embedded bytes without accepting a broken pack.
11. Crash evidence: distinguish a CLR-handled fault from managed/native fatal paths.
    Check reporter coexistence with Unity/Android, completed/partial reports,
    Previous.log and next-launch system-exit recovery with matching symbols.
    Do not add an outer signal logger as a substitute for these checks.

## Evidence and limitations

Keep build identities, APK layout verification, known-answer results, startup
and TLS errors, selected native module evidence and rollback notes together in
ignored local output. Include the whole session context, not only a success line.
Identify who controls the TLS endpoint and which server-side observations are
available; a public test endpoint is narrower evidence than an owned fixture.
Keep lifecycle and TLS verdicts separate so a network failure does not prevent
collecting independent lifecycle evidence. Timeout/EOF does not prove certificate
rejection. An opaque TCP forwarding route can help compare network paths while
keeping TLS and certificate validation on the device; record that route and do
not treat its success as proof of direct-network reliability.

Use this matrix to qualify API 26 ART in-memory DEX, native TLS/provider behavior
and game compatibility. Android profile's upstream synchronous HTTP restriction
is a separate runtime limitation. Capture available logs/logcat alongside the
checks; their absence does not establish a clean run.

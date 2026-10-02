# Runtime source development

Run these commands from the LemonLoader repository root. Normal product builds
consume validated runtime packs; rebuilding CoreCLR is an explicit maintainer
workflow. Runtime hosting and crypto behavior are in [RUNTIME.md](RUNTIME.md).

## Source selection

`eng/runtime-profiles.json` owns the runtime repository URL, version and exact
revision. Android and Bionic share one reviewed source revision. The maintained
fork is `LemonLoaderX/runtime`; common fixes belong on its main branch. The frozen
.NET 10 branch is a separate recovery input, not the active setup target.

```powershell
pwsh -NoProfile -File scripts/setup-runtime.ps1
pwsh -NoProfile -File scripts/build-runtime.ps1 -Plan
pwsh -NoProfile -File scripts/build-runtime.ps1 -RuntimeProfile all
```

Setup selects `../dotnet-runtime` only when HEAD matches the selected pin;
otherwise it creates `.dependencies/dotnet-runtime/<revision>`. Existing sources
are checked without fetching, switching branches or changing local work. A new
cache is detached at the exact fork revision. Runtime setup checks tracked changes,
as the builder does; untracked artifacts links, lock files and local inputs are
preserved. Other dependency setup retains its stricter untracked-file check.
Missing unpublished fork revisions
must be made available by the maintainer; setup never substitutes upstream/main.
For an external checkout, pass `-SourceRoot <checkout>` to setup and build.

## Toolchain and outputs

The builder uses PowerShell 7 and WSL (default distribution Ubuntu-24.04), with
Linux x64 build prerequisites from the selected dotnet/runtime source. Source and
output must be on the same non-C Windows drive, and output must be outside source.
This preserves the Windows sibling layout and prevents source/output recursion.
Use `-Distribution` and `-OutputRoot` to override the defaults.

WSL defaults reuse these user caches; environment variables may override them:

| Input | Environment variable | Default under WSL home |
| --- | --- | --- |
| Linux Android NDK r27d | ANDROID_NDK_ROOT | .cache/lemonloader/android-ndk-r27d |
| Android SDK | ANDROID_SDK_ROOT | .cache/lemonloader/android-sdk |
| JDK 21 | JAVA_HOME | .cache/lemonloader/jdk-21.0.12.1-1 |
| Bionic OpenSSL headers | OPENSSL_INCLUDE_DIR | .cache/lemonloader/openssl-build-headers/extracted/usr/include |

Install the exact SDK requested by the runtime checkout's own global.json; it is
distinct from Loader's product SDK. If dotnet-install's ordinary preview feed
does not contain that exact build, use Microsoft's official dotnet CI feed rather
than downgrading the SDK/compiler. Runtime NuGet.config is passed explicitly to
restore so external artifacts do not change feed discovery.

One source checkout has an exclusive build lock. Its artifacts symlink selects
separate `Output/RuntimeDevelopment/<revision>/<rid>/artifacts` trees. Builds run
sequentially. Bionic alone disables FeatureXplatEventSource and supplies OpenSSL
headers; common options stay identical. Source status/diff, command, log, exit
code and package checksums remain beside each target's outputs, outside releases.
Git for Windows is used through WSL interop when available to avoid expensive
Linux Git stat scans on DrvFS; otherwise Linux Git is used.

An existing non-link source artifacts directory is rejected. Preserve it manually
outside the checkout before building; do not overwrite it or recursively clean
through the artifacts link. When moving a checkout, preserve the link target and
pass the old OutputRoot explicitly if continuing those outputs.

## Local changes

```powershell
pwsh -NoProfile -File scripts/build-runtime.ps1 -RuntimeProfile android `
    -SourceRoot "<edited-checkout>" -Development
```

Locked builds require the configured revision and no tracked edits. Development
allows another HEAD and tracked edits, recording outputs under
`Output/RuntimeDevelopment/local/<actual-commit>/<rid>`. Plan checks paths and
revision without creating outputs or changing artifacts; build also checks the
working tree. Explicit SourceRoot is necessary when a sibling no longer matches
the pin. Build never fetches or changes branches.

## Prepare and package

Use the matching Shipping runtime nupkg and its recorded SHA-256:

```powershell
pwsh -NoProfile -File scripts/build/prepare-runtime-pack.ps1 `
    -RuntimeProfile android -Nupkg "<runtime-pack.nupkg>" `
    -ExpectedSha256 "<sha256>" -RuntimeSourceRoot "<checkout>"
pwsh -NoProfile -File scripts/build/package-runtime.ps1 -RuntimeProfile all
```

Bionic preparation requires OpenSslRoot (Android ARM64 shared libraries) and
OpenSslLicense. Android compiles the matching helper DEX from source;
LinuxAndroidSdkRoot and LinuxJavaHome override its WSL tools. ZIP safety, source
revision, nupkg hash, pack inventory, AArch64 symbols and 16 KiB LOAD alignment
remain checked. Use a new Destination for changed inputs; existing packs are not
overwritten. Pack hashes detect content mismatch, not source authenticity.

Use `-Development` throughout prepare/import/package and product build for local
source packs. Import places them under Output/RuntimePacks/local, packaging under
Output/DevelopmentRuntimeArtifacts, and Loader builds under
Output/DevelopmentReleases. Pass the pack explicitly to product build with
CoreClrRuntimePackRoot. Development never relaxes ABI, RID, crypto or file-content
validation, and formal staging rejects development packs.

## Validation and publication

Runtime archives contain runtime inputs, provenance, licenses and pack inventory.
Loader active Release/APK layout 9 uses minimal payload configuration and embeds
Android crypto DEX in libmain.so; it does not ship installed identity/digest
inventories. Historical layout 8 and external DEX compatibility are separate.
See [ARTIFACTS.md](ARTIFACTS.md) and [DEPLOYMENT.md](DEPLOYMENT.md).

```powershell
pwsh -NoProfile -File scripts/test/test-source-dependencies.ps1
pwsh -NoProfile -File scripts/test/test-runtime-profiles.ps1
pwsh -NoProfile -File scripts/test/test-runtime-source-build.ps1
```

Host/source fixtures verify orchestration and contracts, not ART or real TLS.
Use the [device procedure](../maintenance/embedded-crypto-acceptance.md) for crypto,
handler coexistence, application lifecycle and exact-build symbol matching.
OpenSSL source/security review, additional games/devices and physical 16 KiB pages
remain independent release gates. Preserve source changes in reviewed forks;
never rewrite a built SO or substitute old crypto shims.

Publish the reviewed runtime revision and archives before a consuming Loader tag.
The runtime tag is coreclr-<version>-<first-12-revision-chars>, with Android/Bionic
assets and SHA-256 sidecars. Loader CI consumes those exact assets. Do not publish
development packs or relabel them as formal builds. Upstream updates require
reviewing one revision, updating both active pins, rebuilding/preparing both
targets and repeating acceptance. Do not reapply legacy fixes already upstream.
Frozen recovery uses build-android-managed-runtime.ps1 and
publish-android-runtime-pack.ps1 with explicit -Legacy and a separate checkout.

# LemonLoader

Android ARM64 [MelonLoader](https://github.com/LavaGang/MelonLoader) for Unity
IL2CPP games, maintained by [LemonLoaderX](https://github.com/LemonLoaderX).
The desktop upstream baseline remains in this repository.

The supported target is API 26+, `arm64-v8a`, .NET 11 CoreCLR and 16 KiB-compatible
native libraries. Android uses platform JNI crypto with helpers embedded in
`libmain.so`; Bionic uses private OpenSSL. Both are preview profiles; see the
[support boundary](docs/android/STATUS.md). Layout 8, MonoVM, Android Mono games
and 32-bit ABIs are unsupported.

This repository builds game-independent Loader archives.
[LemonLoader.Patcher](https://github.com/LemonLoaderX/LemonLoader.Patcher) is an
optional convenience tool. It exposes independent Interop generation, injection
using existing DLLs and APK alignment/signing, plus a combined one-step workflow.
Scripts and ZIP editors can install the same Loader through the documented
[file layout](docs/android/ARTIFACTS.md) and [manual steps](docs/android/USAGE.md#manual-injection).

## Start here

- [Install and use](docs/android/USAGE.md)
- [Build](docs/android/BUILDING.md)
- [Documentation by task](docs/README.md)
- [Contribute](CONTRIBUTING.md), [report vulnerabilities](SECURITY.md)

Loader and Patcher own independent source pins and workflows. Matching sibling
forks are optional; otherwise setup uses private revision caches. Normal product
builds consume validated runtime packs. Compiling dotnet/runtime is a separate
maintainer workflow, not an implicit step of every Loader build.

## License

LemonLoader retains MelonLoader's [Apache-2.0 license](LICENSE.md).
Third-party sources and release inputs retain their own licenses and notices.
The project is not affiliated with LavaGang, Unity Technologies or a game.

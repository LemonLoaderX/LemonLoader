# Android build support

This directory contains project files used to acquire or describe Android build
inputs. It does not contain generated artifacts.

`RuntimePack/AndroidRuntimePack.csproj` is a restore-only project that downloads
the pinned `Microsoft.NETCore.App.Runtime.linux-bionic-arm64` package selected by
`AndroidDotnetRuntimeVersion`. The staging workflow consumes the restored NuGet
package and creates the private runtime tree under `Output`.

Do not place decoded APK content, generated Interop assemblies, extracted
runtime files, or compiler output here. Those belong under `Output` and remain
ignored by Git.

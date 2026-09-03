using MelonLoader;
using MelonLoader.Utils;
using System.Security.Cryptography;
using System.Text.Json;
using RuntimeNativeLibrary = System.Runtime.InteropServices.NativeLibrary;

[assembly: MelonInfo(
    typeof(LemonLoader.Tests.AndroidSmokeMod),
    "Android Smoke Mod",
    "1.0.0",
    "LemonLoader")]

namespace LemonLoader.Tests;

public sealed class AndroidSmokeMod : MelonMod
{
    private bool _firstUpdateLogged;
    private bool _firstFixedUpdateLogged;
    private bool _firstLateUpdateLogged;
    private bool _firstOnGuiLogged;

    public override void OnInitializeMelon()
    {
        LoggerInstance.Msg("Initialize");
        ProbeManagedRuntimeIdentity();
        ProbeRuntimeIdentityFile();
        _ = ProbeJniWorkerAsync();

        string probePath = Path.Combine(
            MelonEnvironment.UserDataDirectory,
            "AndroidSmoke.https-url");
        if (File.Exists(probePath))
        {
            string url = File.ReadAllText(probePath).Trim();
            if (Uri.TryCreate(url, UriKind.Absolute, out Uri? uri) && uri.Scheme == Uri.UriSchemeHttps)
                _ = ProbeHttpsAsync(uri);
            else
                LoggerInstance.Error("HttpsRequestFailed invalid probe URL");
        }
    }

    private async Task ProbeHttpsAsync(Uri uri)
    {
        try
        {
            using HttpClient client = new() { Timeout = TimeSpan.FromSeconds(15) };
            using HttpResponseMessage response = await client.GetAsync(uri).ConfigureAwait(false);
            response.EnsureSuccessStatusCode();
            byte[] content = await response.Content.ReadAsByteArrayAsync().ConfigureAwait(false);
            LoggerInstance.Msg(
                $"HttpsRequest {(int)response.StatusCode} {content.Length} {uri.Host}");
        }
        catch (Exception exception)
        {
            LoggerInstance.Error($"HttpsRequestFailed {exception.Message}");
        }
    }

    public override void OnSceneWasLoaded(int buildIndex, string sceneName)
    {
        LoggerInstance.Msg($"SceneLoaded {buildIndex} {sceneName}");
    }

    public override void OnUpdate()
    {
        if (_firstUpdateLogged)
            return;

        _firstUpdateLogged = true;
        LoggerInstance.Msg("FirstUpdate");
    }

    public override void OnLateUpdate()
    {
        if (_firstLateUpdateLogged)
            return;

        _firstLateUpdateLogged = true;
        LoggerInstance.Msg("FirstLateUpdate");
    }

    private void ProbeRuntimeIdentityFile()
    {
        try
        {
            string dotnetRoot = Environment.GetEnvironmentVariable("MELONLOADER_DOTNET_ROOT")
                ?? throw new InvalidOperationException("MELONLOADER_DOTNET_ROOT is unset");
            using JsonDocument document = JsonDocument.Parse(File.ReadAllText(
                Path.Combine(dotnetRoot, "runtime-identity.json")));
            JsonElement identity = document.RootElement;
            string backend = identity.GetProperty("backend").GetString() ?? "<null>";
            string version = identity.GetProperty("runtimeVersion").GetString() ?? "<null>";
            string hostingModel = identity.GetProperty("hostingModel").GetString() ?? "<null>";
            string expectedHash = identity.GetProperty("engineSha256").GetString() ?? "";
            string engine = Path.Combine(
                dotnetRoot,
                "shared",
                "Microsoft.NETCore.App",
                version,
                "libcoreclr.so");
            using FileStream input = File.OpenRead(engine);
            using SHA256 sha256 = SHA256.Create();
            string actualHash = Convert.ToHexString(sha256.ComputeHash(input)).ToLowerInvariant();
            LoggerInstance.Msg(
                $"RuntimeIdentityFile {backend} {version} {hostingModel} Hash {actualHash == expectedHash}");
        }
        catch (Exception exception)
        {
            LoggerInstance.Error($"RuntimeIdentityFileFailed {exception.Message}");
        }
    }

    private void ProbeManagedRuntimeIdentity()
    {
        nint runtime = 0;
        try
        {
            runtime = RuntimeNativeLibrary.Load("libcoreclr.so");
            bool coreClr = RuntimeNativeLibrary.TryGetExport(runtime, "coreclr_initialize", out _);
            bool monoVm = RuntimeNativeLibrary.TryGetExport(runtime, "monovm_initialize", out _);
            string maps = File.ReadAllText("/proc/self/maps");
            bool privateMap = maps.Contains(
                "/dotnet/shared/Microsoft.NETCore.App/",
                StringComparison.Ordinal) &&
                maps.Contains("/libcoreclr.so", StringComparison.Ordinal);
            LoggerInstance.Msg($"RuntimeIdentity CoreClr {coreClr} MonoVm {monoVm} Maps {privateMap}");
        }
        catch (Exception exception)
        {
            LoggerInstance.Error($"RuntimeIdentityFailed {exception.Message}");
        }
        finally
        {
            if (runtime != 0)
                RuntimeNativeLibrary.Free(runtime);
        }
    }

    private async Task ProbeJniWorkerAsync()
    {
        await Task.Run(() =>
        {
            try
            {
                int version = MelonLoader.Java.JNI.GetVersion();
                bool payloadExists = APKAssetManager.DoesAssetExist("LemonLoader/payload.json");
                LoggerInstance.Msg($"JniWorker {version:X} {payloadExists}");
            }
            finally
            {
                MelonLoader.Java.JNI.DetachCurrentThread();
            }
        }).ConfigureAwait(false);
    }

    public override void OnFixedUpdate()
    {
        if (_firstFixedUpdateLogged)
            return;

        _firstFixedUpdateLogged = true;
        LoggerInstance.Msg("FirstFixedUpdate");
    }

    public override void OnGUI()
    {
        if (_firstOnGuiLogged)
            return;

        _firstOnGuiLogged = true;
        LoggerInstance.Msg("FirstOnGUI");
    }

    public override void OnApplicationQuit()
    {
        LoggerInstance.Msg("ApplicationQuit");
    }
}

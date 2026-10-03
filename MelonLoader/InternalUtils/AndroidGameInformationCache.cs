#if ANDROID
#nullable enable
using System;
using System.IO;
using System.Text.Json;

namespace MelonLoader.InternalUtils;

internal static class AndroidGameInformationCache
{
    private static string PathForCache => Path.Combine(
        Environment.GetEnvironmentVariable("MELONLOADER_BASE_DIR") ?? "", "MelonLoader", "GameInformation.json");

    private static string? Identity(string? versionOverride)
    {
        var token = Environment.GetEnvironmentVariable("MELONLOADER_APK_UPDATE_TOKEN");
        var basePath = Environment.GetEnvironmentVariable("MELONLOADER_BASE_DIR");
        if (string.IsNullOrEmpty(token) || string.IsNullOrEmpty(basePath))
            return null;
        return token + "|" + typeof(UnityInformationHandler).Module.ModuleVersionId + "|" + versionOverride;
    }

    internal static string[]? Read(string? versionOverride)
    {
        var identity = Identity(versionOverride);
        if (identity == null)
            return null;
        try
        {
            var file = new FileInfo(PathForCache);
            if (!file.Exists || file.Length > 16 * 1024)
                return null;
            var values = JsonSerializer.Deserialize<string[]>(File.ReadAllText(file.FullName));
            if (values?.Length != 5 || values[0] != identity)
                return null;
            for (int i = 1; i < values.Length; i++)
                if (string.IsNullOrEmpty(values[i])) return null;
            return values;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException)
        {
            return null;
        }
    }

    internal static void Write(string? versionOverride, string name, string developer, string gameVersion, string engineVersion)
    {
        var identity = Identity(versionOverride);
        if (identity == null)
            return;
        var temporary = PathForCache + ".tmp";
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(PathForCache)!);
            File.WriteAllText(temporary, JsonSerializer.Serialize(new[] { identity, name, developer, gameVersion, engineVersion }));
            File.Move(temporary, PathForCache, true);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            // This optional cache must not prevent parsing on the next launch.
        }
        finally
        {
            try { if (File.Exists(temporary)) File.Delete(temporary); }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException) { }
        }
    }
}
#endif

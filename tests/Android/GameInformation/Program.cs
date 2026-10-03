using MelonLoader;
using MelonLoader.InternalUtils;
using MelonLoader.Utils;
using AssetsTools.NET.Extra;

byte[] managers = Fixtures.Managers();
var control = new AssetsManager();
try
{
    using var input = new MemoryStream(managers);
    var file = control.LoadAssetsFile(input, "fixture", false);
    var settings = control.GetBaseField(file, file.file.GetAssetsOfType(AssetClassID.PlayerSettings)[0]);
    if (settings.Get("productName").AsString != "Fixture Game")
        throw new Exception("Synthetic PlayerSettings fixture is invalid.");
}
finally { control.UnloadAll(); }
var scenarios = new (string Name, string Path, byte[] Data, bool Success)[]
{
    ("standalone", "globalgamemanagers", managers, true),
    ("legacy standalone", "mainData", managers, true),
    ("uncompressed bundle", "data.unity3d", Fixtures.Bundle(managers), true),
    ("bundle without managers", "data.unity3d", Fixtures.Bundle(managers, "other"), false),
    ("invalid file", "globalgamemanagers", new byte[64], false),
    ("invalid bundle", "data.unity3d", new byte[64], false)
};
int failures = 0;
Environment.SetEnvironmentVariable("MELONLOADER_APK_UPDATE_TOKEN", null);
foreach (var scenario in scenarios)
{
    foreach (var property in typeof(UnityInformationHandler).GetProperties())
        property.SetValue(null, property.PropertyType.IsValueType ? Activator.CreateInstance(property.PropertyType) : null);
    APKAssetManager.Files.Clear();
    APKAssetManager.Opened.Clear();
    MelonDebug.Errors.Clear();
    APKAssetManager.Files.Add("bin/Data/" + scenario.Path, scenario.Data);
    UnityInformationHandler.Setup();
    bool valuesMatch = UnityInformationHandler.GameName == "Fixture Game" &&
        UnityInformationHandler.GameDeveloper == "Fixture Studio" &&
        UnityInformationHandler.GameVersion == "1.2.3" &&
        UnityInformationHandler.EngineVersion.ToString() == "2021.3.0f1";
    bool fallback = UnityInformationHandler.GameName == "UNKNOWN" &&
        UnityInformationHandler.GameDeveloper == "UNKNOWN" &&
        UnityInformationHandler.GameVersion == "UNKNOWN";
    bool closed = APKAssetManager.Opened.Count > 0 && APKAssetManager.Opened.All(stream => stream.Closed);
    bool passed = closed && (scenario.Success ? valuesMatch && MelonDebug.Errors.Count == 0 : fallback);
    Console.WriteLine($"{(passed ? "PASS" : "FAIL")} {scenario.Name}: values={valuesMatch} allStreamsClosed={closed}");
    if (!passed)
    {
        failures++;
        foreach (string error in MelonDebug.Errors) Console.WriteLine(error);
    }
}
var cacheRoot = Path.Combine(Path.GetTempPath(), "lemon-gameinfo-" + Guid.NewGuid().ToString("N"));
Environment.SetEnvironmentVariable("MELONLOADER_BASE_DIR", cacheRoot);
Environment.SetEnvironmentVariable("MELONLOADER_APK_UPDATE_TOKEN", "apk-first");
try
{
    APKAssetManager.Files.Clear();
    APKAssetManager.Files.Add("bin/Data/globalgamemanagers", managers);
    UnityInformationHandler.Setup();
    var cacheFile = Path.Combine(cacheRoot, "MelonLoader", "GameInformation.json");
    if (!File.Exists(cacheFile)) throw new Exception("Parsed information was not cached.");
    APKAssetManager.Files.Clear();
    APKAssetManager.Opened.Clear();
    foreach (var property in typeof(UnityInformationHandler).GetProperties())
        property.SetValue(null, property.PropertyType.IsValueType ? Activator.CreateInstance(property.PropertyType) : null);
    UnityInformationHandler.Setup();
    if (UnityInformationHandler.GameName != "Fixture Game" || APKAssetManager.Opened.Count != 0)
        throw new Exception("Cached startup still read game assets.");
    if (AndroidGameInformationCache.Read("2022.1.0f1") != null)
        throw new Exception("Version override did not invalidate cache.");
    Environment.SetEnvironmentVariable("MELONLOADER_APK_UPDATE_TOKEN", "apk-next");
    if (AndroidGameInformationCache.Read(LoaderConfig.Current.UnityEngine.VersionOverride) != null)
        throw new Exception("APK update did not invalidate cache.");
    Environment.SetEnvironmentVariable("MELONLOADER_APK_UPDATE_TOKEN", "apk-first");
    File.WriteAllText(cacheFile, "invalid-json");
    if (AndroidGameInformationCache.Read(LoaderConfig.Current.UnityEngine.VersionOverride) != null)
        throw new Exception("Malformed cache accepted.");
    APKAssetManager.Files.Add("bin/Data/globalgamemanagers", managers);
    UnityInformationHandler.Setup();
    if (AndroidGameInformationCache.Read(LoaderConfig.Current.UnityEngine.VersionOverride) == null)
        throw new Exception("Malformed cache did not recover from real game data.");
    Console.WriteLine("PASS cache hit avoids assets; APK/override invalidation and malformed-cache recovery");
}
finally
{
    Environment.SetEnvironmentVariable("MELONLOADER_BASE_DIR", null);
    Environment.SetEnvironmentVariable("MELONLOADER_APK_UPDATE_TOKEN", null);
    if (Directory.Exists(cacheRoot)) Directory.Delete(cacheRoot, true);
}
return failures == 0 ? 0 : 1;

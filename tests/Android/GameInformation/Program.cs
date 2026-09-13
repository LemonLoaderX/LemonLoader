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
return failures == 0 ? 0 : 1;

using MelonLoader;
using MelonLoader.Utils;
using Tomlet;

Directory.CreateDirectory(MelonEnvironment.UserDataDirectory);
int failures = 0;
int savedEvents = 0;
MelonPreferences.OnPreferencesSaved.Subscribe(_ => savedEvents++);

void Check(string name, bool condition)
{
    Console.WriteLine($"{(condition ? "PASS" : "FAIL")} {name}");
    if (!condition) failures++;
}

bool HasSuccess() => MelonLogger.Messages.Any(message =>
    message.StartsWith("MelonPreferences Saved to ") || message == "Preferences Saved!");

void CheckSave(string name, Action save, bool expectedSuccess, bool expectedError = false)
{
    MelonLogger.Messages.Clear();
    int before = savedEvents;
    save();
    Check(name + " success log", HasSuccess() == expectedSuccess);
    Check(name + " saved event", (savedEvents > before) == expectedSuccess);
    Check(name + " error log", MelonLogger.Messages.Any(m => m.StartsWith("Error while Saving")) == expectedError);
}

var category = MelonPreferences.CreateCategory("Example.Nested");
category.SetFilePath(Path.Combine(MelonEnvironment.UserDataDirectory, "normal.cfg"), false, false);
category.CreateEntry("Value", 42, description: "Retain comments and nested values");
CheckSave("ordinary success", () => category.SaveToFile(), true);
MelonLogger.Messages.Clear();
int beforeSilentSave = savedEvents;
category.SaveToFile(false);
Check("silent save suppresses success log only", !HasSuccess() && savedEvents == beforeSilentSave + 1);
var parsed = TomlParser.ParseFile(category.File.FilePath);
Check("saved value round trip", parsed.GetSubTable("Example").GetSubTable("Nested").GetInteger("Value") == 42);

category.File.ShouldSave = false;
CheckSave("ordinary disabled", () => category.SaveToFile(), false);
category.File.ShouldSave = true;
category.File.FilePath = Path.Combine(MelonEnvironment.UserDataDirectory, "missing", "normal.cfg");
CheckSave("ordinary write failure", () => category.SaveToFile(), false, true);
CheckSave("ordinary fallback", () => category.SaveToFile(), false);
Check("write failure clears saving flag", !category.File.IsSaving);

var reflective = MelonPreferences.CreateCategory<Settings>("Reflective");
reflective.SetFilePath(Path.Combine(MelonEnvironment.UserDataDirectory, "reflective.cfg"), false, false);
CheckSave("reflective success", () => reflective.SaveToFile(), true);
reflective.File.ShouldSave = false;
CheckSave("reflective disabled", () => reflective.SaveToFile(), false);
reflective.File.ShouldSave = true;
reflective.File.FilePath = Path.Combine(MelonEnvironment.UserDataDirectory, "missing", "reflective.cfg");
CheckSave("reflective write failure", () => reflective.SaveToFile(), false, true);
CheckSave("reflective fallback", () => reflective.SaveToFile(), false);

// A batch must continue saving healthy files without reporting the whole batch as successful.
var healthy = MelonPreferences.CreateCategory("Healthy");
healthy.SetFilePath(Path.Combine(MelonEnvironment.UserDataDirectory, "healthy.cfg"), false, false);
healthy.CreateEntry("Value", 9);
MelonLogger.Messages.Clear();
MelonPreferences.Save();
Check("batch with fallback files has no success log", !HasSuccess());
Check("batch still writes healthy default file", System.IO.File.Exists(MelonPreferences.DefaultFile.FilePath));
Check("batch still writes healthy file after failed files", System.IO.File.Exists(healthy.File.FilePath));
MelonPreferences.Categories.Clear();
MelonPreferences.ReflectiveCategories.Clear();
MelonPreferences.PrefFiles.Clear();
CheckSave("healthy batch", MelonPreferences.Save, true);
MelonPreferences.DefaultFile.FilePath = Path.Combine(MelonEnvironment.UserDataDirectory, "missing", "default.cfg");
CheckSave("batch write failure", MelonPreferences.Save, false, true);
CheckSave("batch fallback", MelonPreferences.Save, false);

return failures == 0 ? 0 : 1;

public class Settings
{
    public int Value { get; set; } = 7;
}

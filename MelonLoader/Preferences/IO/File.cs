using System.Linq;
using Tomlet;
using Tomlet.Exceptions;
using Tomlet.Models;

namespace MelonLoader.Preferences.IO
{
    internal class File
    {
        private bool _waserror = false;

        internal bool WasError
        {
            get => _waserror;
            set
            {
                if (value == true)
                {
                    MelonLogger.Warning($"Defaulting {FilePath} to Fallback Functionality to further avoid File Corruption...");
                    IsSaving = false;
                    FileWatcher.Destroy();
                }

                _waserror = value;
            }
        }

        internal string FilePath = null;
        internal string LegacyFilePath = null;
        internal bool IsSaving = false;
        internal bool ShouldSave = true;
        internal TomlDocument document = TomlDocument.CreateEmpty();
        internal Watcher FileWatcher = null;

        internal File(string filepath, string legacyfilepath = null, bool shouldsave = true)
        {
            FilePath = filepath;
            LegacyFilePath = legacyfilepath;
            ShouldSave = shouldsave;
            FileWatcher = new Watcher(this);
        }

        internal void LegacyLoad()
        {
            if (string.IsNullOrEmpty(LegacyFilePath) || !System.IO.File.Exists(LegacyFilePath))
                return;
            string filestr = System.IO.File.ReadAllText(LegacyFilePath);
            string[] lines = filestr.Split('\n');
            string category = null;

            foreach (string line in lines)
            {
                if (string.IsNullOrEmpty(line))
                    continue;
                string newline = line.Replace("\n", "").Replace("\r", "").Replace(" ", "");
                if (newline.Contains("[") && newline.Contains("]"))
                {
                    category = newline.Replace("[", "").Replace("]", "");
                    continue;
                }

                if (!newline.Contains("="))
                    continue;
                string[] parts = line.Split('=');
                if (string.IsNullOrEmpty(parts[0]) || string.IsNullOrEmpty(parts[1]))
                    continue;
                if (parts[1].ToLower().StartsWith("true") || parts[1].ToLower().StartsWith("false"))
                    InsertIntoDocument(category, parts[0], TomletMain.ValueFrom(parts[1].ToLower().StartsWith("true")));
                else if (int.TryParse(parts[1], out int val_int))
                    InsertIntoDocument(category, parts[0], TomletMain.ValueFrom(val_int));
                else if (float.TryParse(parts[1], out float val_float))
                    InsertIntoDocument(category, parts[0], TomletMain.ValueFrom(val_float));
                else
                    InsertIntoDocument(category, parts[0], TomletMain.ValueFrom(parts[1].Replace("\r", "")));
            }
            
            MelonPreferences.OnPreferencesLoaded.Invoke(FilePath);
        }

        internal void Load()
        {
            if (_waserror
                || !System.IO.File.Exists(FilePath))
                return;
            
            document = TomlParser.ParseFile(FilePath);
            
            MelonPreferences.OnPreferencesLoaded.Invoke(FilePath);
        }

        internal void Save()
        {
            if (_waserror || !ShouldSave)
                return;
            
            IsSaving = true;
            
            System.IO.File.WriteAllText(FilePath, document.SerializedValue);
            
            if ((LegacyFilePath != null) && System.IO.File.Exists(LegacyFilePath))
                System.IO.File.Delete(LegacyFilePath);

            MelonPreferences.OnPreferencesSaved.Invoke(FilePath);
        }
        
        private static string QuoteKey(string key) =>
            key.Contains('"') 
                ? $"'{key}'"
                : $"\"{key}\"";

        private static bool IsNullOrWhiteSpace(string value) =>
            string.IsNullOrEmpty(value) || value.Trim().Length == 0;

        private TomlTable GetCategoryTable(string category, bool create)
        {
            if (IsNullOrWhiteSpace(category))
                return null;

            TomlTable current = document;
            foreach (string part in category.Split('.'))
            {
                if (IsNullOrWhiteSpace(part))
                    return null;

                if (!current.ContainsKey(part))
                {
                    if (!create)
                        return null;
                    current.PutValue(part, new TomlTable());
                }

                try
                {
                    current = current.GetSubTable(part);
                }
                catch (TomlTypeMismatchException)
                {
                    return null;
                }
                catch (TomlNoSuchValueException)
                {
                    return null;
                }
            }

            return current;
        }

        internal void InsertIntoDocument(string category, string key, TomlValue value, bool should_inline = false)
        {
            var categoryTable = GetCategoryTable(category, true);
            if (categoryTable == null)
                return;

            categoryTable.ForceNoInline = !should_inline;
            categoryTable.PutValue(QuoteKey(key), value);
        }

        internal bool RemoveEntryFromDocument(string category, string key)
        {
            var categoryTable = GetCategoryTable(category, false);
            if (categoryTable == null)
                return false;
            return categoryTable.Entries.Remove(key);
        }

        internal bool RemoveCategoryFromDocument(string category)
        {
            if (IsNullOrWhiteSpace(category))
                return false;

            string[] parts = category.Split('.');
            TomlTable parent = parts.Length == 1
                ? document
                : GetCategoryTable(string.Join(".", parts, 0, parts.Length - 1), false);
            if (parent == null)
                return false;
            return parent.Entries.Remove(parts[^1]);
        }

        internal bool RenameEntryInDocument(string category, string key, string newKey)
        {
            var categoryTable = GetCategoryTable(category, false);
            if (categoryTable == null)
                return false;
            if (!categoryTable.Entries.ContainsKey(key) || categoryTable.Entries.ContainsKey(newKey))
                return false;

            TomlValue value = categoryTable.Entries[key];
            categoryTable.Entries.Remove(key);
            categoryTable.Entries.Add(newKey, value);
            return true;
        }

        internal TomlTable TryGetCategoryTable(string category)
        {
            lock (document)
            {
                return GetCategoryTable(category, false);
            }
        }

        internal void SetupEntryFromRawValue(MelonPreferences_Entry entry)
        {
            lock (document)
            {
                var categoryTable = GetCategoryTable(entry.Category.Identifier, false);
                if (categoryTable == null)
                    return;

                try
                {
                    var value = categoryTable.GetValue(QuoteKey(entry.Identifier));
                    entry.Load(value);
                }
                catch (TomlTypeMismatchException) { }
                catch (TomlNoSuchValueException) { }
            }
        }
    }
}

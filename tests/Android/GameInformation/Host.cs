using AssetsTools.NET;
using AssetsTools.NET.Extra;

namespace MelonLoader.Utils
{
    // Real AssetsTools parsing; only Android's asset transport is replaced.
    static class APKAssetManager
    {
        internal static readonly Dictionary<string, byte[]> Files = new();
        internal static readonly List<TrackedStream> Opened = new();
        internal static bool DoesAssetExist(string path) => Files.ContainsKey(path);
        internal static byte[] GetAssetBytes(string path) => Files[path];
        internal static Stream? GetAssetStream(string path)
        {
            if (!Files.TryGetValue(path, out var data)) return null;
            var stream = new TrackedStream(data); Opened.Add(stream); return stream;
        }
    }
    sealed class TrackedStream(byte[] data) : MemoryStream(data, false)
    {
        internal bool Closed;
        protected override void Dispose(bool disposing) { Closed = true; base.Dispose(disposing); }
    }
}
namespace MelonLoader
{
    static class MelonEnvironment { internal static string UnityGameDataDirectory => "bin/Data"; }
    sealed class LoaderConfig
    {
        internal static LoaderConfig Current = new();
        internal UnityOptions UnityEngine = new();
        internal sealed class UnityOptions { internal string VersionOverride = ""; }
    }
    static class MelonDebug
    {
        internal static readonly List<string> Errors = new();
        internal static void Error(string message) => Errors.Add(message);
    }
    static class MelonLogger
    {
        internal static void WriteLine(Logging.ColorARGB color) { }
        internal static void WriteSpacer() { }
        internal static void Msg(string message) { }
        internal static void Warning(string message) { }
    }
    static class MelonUtils
    {
        internal static ClassPackageFile LoadIncludedClassPackage(this AssetsManager manager) =>
            manager.LoadClassPackage(typeof(MelonUtils).Assembly.GetManifestResourceStream("classdata.tpk"));
    }
}
namespace MelonLoader.Logging { enum ColorARGB { Magenta } }

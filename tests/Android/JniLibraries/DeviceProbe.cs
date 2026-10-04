using System.Reflection;
using System.Runtime.Loader;
using MelonLoader;
using MelonLoader.Java;
using MelonLoader.Utils;

[assembly: MelonInfo(typeof(LemonLoader.Tests.JniLibraries.DeviceProbe), "JNI Library Probe", "1.0.0", "LemonLoader")]

namespace LemonLoader.Tests.JniLibraries;

public sealed class DeviceProbe : MelonMod
{
    private bool firstUpdate;
    private AssemblyLoadContext? context;

    public override unsafe void OnInitializeMelon()
    {
        try
        {
            string directory = Path.Combine(MelonEnvironment.UserDataDirectory, "JniLibraries");
            string candidate = File.ReadAllText(Path.Combine(directory, "candidate.txt")).Trim();
            _ = JNI.GetVersion();
            nint vm = (nint)typeof(JNI).GetField("lastVmPtr", BindingFlags.Static | BindingFlags.NonPublic)!.GetValue(null)!;
            nint env = 0;
            var get = (delegate* unmanaged<nint, nint*, int, int>)(*(nint**)vm)[6];
            if (get(vm, &env, 0x10006) != 0) throw new InvalidOperationException("No existing JNI environment.");
            var asset = (JObject)typeof(APKAssetManager).GetField("assetManager", BindingFlags.Static | BindingFlags.NonPublic)!.GetValue(null)!;
            using var unity = JNI.FindClass("com/unity3d/player/UnityPlayer");
            using var activity = JNI.GetStaticObjectField<JObject>(unity, unity.GetStaticFieldID("currentActivity", "Landroid/app/Activity;"));
            using var activityType = JNI.GetObjectClass(activity);
            using var loader = JNI.CallObjectMethod<JObject>(activity, activityType.GetMethodID("getClassLoader", "()Ljava/lang/ClassLoader;"));
            if (JNI.ExceptionCheck()) { JNI.ExceptionClear(); throw new InvalidOperationException("No application classloader."); }
            context = new CandidateContext(directory);
            Assembly host = context.LoadFromAssemblyPath(Path.Combine(directory, "Host.dll"));
            host.GetType("LemonLoader.Tests.JniLibraries.Suites")!.GetMethod("Run")!.Invoke(null,
                [candidate, vm, env, new Action<string>(line => LoggerInstance.Msg(line)), asset.Handle, loader.Handle]);
        }
        catch (Exception e)
        {
            LoggerInstance.Error($"FAIL JNI evaluation: {e}");
        }
    }

    public override void OnUpdate()
    {
        if (firstUpdate) return;
        firstUpdate = true;
        LoggerInstance.Msg("FRAME after evaluation");
    }

    private sealed class CandidateContext(string directory) : AssemblyLoadContext("JNI evaluation", isCollectible: false)
    {
        protected override Assembly? Load(AssemblyName name)
        {
            string path = Path.Combine(directory, name.Name + ".dll");
            return File.Exists(path) ? LoadFromAssemblyPath(path) : null;
        }
    }
}

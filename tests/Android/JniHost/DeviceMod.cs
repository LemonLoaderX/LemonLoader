using MelonLoader;
using MelonLoader.Java;
using MelonLoader.Utils;

[assembly: MelonInfo(typeof(LemonLoader.Tests.JniLibraries.DeviceMod), "JNI Migration Probe", "1.0.0", "LemonLoader")]

namespace LemonLoader.Tests.JniLibraries;

public sealed class DeviceMod : MelonMod
{
    private bool firstFrame;
    public override void OnInitializeMelon()
    {
        try
        {
            Suites.Run("java-interop", JNI.JavaVM, 0, line => LoggerInstance.Msg(line));
            using (var integers = JNI.FindClass("java/lang/Integer"))
            using (var invalid = JNI.NewString("invalid"))
            {
                try
                {
                    integers.CallStaticMethod<int>("parseInt", "(Ljava/lang/String;)I", invalid);
                    throw new Exception("Java exception missing.");
                }
                catch (JThrowableException e)
                {
                    if (!e.JavaStackTrace.Contains("NumberFormatException"))
                        throw new Exception("Java stack trace missing.", e);
                    LoggerInstance.Msg("PASS Java stack trace");
                }
            }
            using var asset = APKAssetManager.GetAssetStream("LemonLoader/payload.json");
            if (asset == null || asset.ReadByte() < 0) throw new Exception("Payload asset unreadable.");
            if (APKAssetManager.GetAssetStream("LemonLoader/absent-jni-migration-fixture") != null)
                throw new Exception("Missing asset accepted.");
            LoggerInstance.Msg("PASS asset read/missing file");
            Task.Run(() =>
            {
                using var thread = JNI.AttachCurrentThread();
                using var unity = JNI.FindClass("com.unity3d.player.UnityPlayer");
                using var activity = unity.GetStaticObjectField<JObject>("currentActivity", "Landroid/app/Activity;");
                if (activity.IsNull) throw new Exception("No current activity.");
                LoggerInstance.Msg("PASS application class on CLR worker");
            }).GetAwaiter().GetResult();
        }
        catch (Exception e) { LoggerInstance.Error("FAIL JNI migration: " + e); }
    }
    public override void OnUpdate()
    {
        if (firstFrame) return;
        firstFrame = true;
        LoggerInstance.Msg("FRAME after migration");
    }
}

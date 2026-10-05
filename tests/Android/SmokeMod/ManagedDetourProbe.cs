using System.Reflection;
using System.Runtime.CompilerServices;
using HarmonyLib;
using MonoMod.RuntimeDetour;
using MonoMod.RuntimeDetour.Platforms;

namespace LemonLoader.Tests;

internal static class ManagedDetourProbe
{
    [MethodImpl(MethodImplOptions.NoInlining)]
    private static int Target(int value) => value + 7;

    private static void Prefix(ref int value) => value *= 2;
    private static void Postfix(ref int __result) => __result += 35;

    internal static int Run()
    {
        var harmony = new HarmonyLib.Harmony("LemonLoader.ManagedDetourProbe");
        var target = typeof(ManagedDetourProbe).GetMethod(nameof(Target), BindingFlags.NonPublic | BindingFlags.Static)!;
        var invoke = target.CreateDelegate<Func<int, int>>();
        int recompilations = 0;
        var runtime = DetourHelper.Runtime;
        if (runtime is DetourRuntimeNET110Platform &&
            !ReferenceEquals(runtime, DetourRuntimeNETCorePlatform.Create()))
            throw new InvalidOperationException("The .NET 11 JIT hook owner was replaced by a second factory call.");
        OnMethodCompiledEvent compiled = (method, _, _) =>
        {
            if (method.Equals(target))
                Interlocked.Increment(ref recompilations);
        };
        runtime.OnMethodCompiled += compiled;
        try
        {
            Check(false, "baseline", target, invoke);
            for (int round = 0; round < 2; round++)
            {
                harmony.Patch(target,
                    prefix: new HarmonyMethod(typeof(ManagedDetourProbe), nameof(Prefix)),
                    postfix: new HarmonyMethod(typeof(ManagedDetourProbe), nameof(Postfix)));
                Check(true, "patch", target, invoke);
                Task.Run(() => Check(true, "worker", target, invoke)).GetAwaiter().GetResult();
                Thread.Sleep(2000);
                Check(true, "delayed patch", target, invoke);
                harmony.UnpatchSelf();
                Check(false, "unpatch", target, invoke);
                Thread.Sleep(2000);
                Check(false, "delayed unpatch", target, invoke);
            }
        }
        catch (Exception exception)
        {
            throw new InvalidOperationException($"Managed detour recompilation notifications: {recompilations}.", exception);
        }
        finally
        {
            harmony.UnpatchSelf();
            runtime.OnMethodCompiled -= compiled;
        }
        return recompilations;
    }

    private static void Check(bool patched, string phase, MethodInfo method, Func<int, int> invoke)
    {
        for (int i = 0; i < 100000; i++)
        {
            int expected = patched ? i * 2 + 42 : i + 7;
            int direct = Target(i);
            int delegated = invoke(i);
            if (direct != expected || delegated != expected)
                throw new InvalidOperationException($"Managed detour failed during {phase}, iteration {i}: direct={direct}, delegate={delegated}, expected={expected}.");
        }
        if ((int)method.Invoke(null, [3])! != (patched ? 48 : 10))
            throw new InvalidOperationException($"Reflection detour failed during {phase}.");
    }
}

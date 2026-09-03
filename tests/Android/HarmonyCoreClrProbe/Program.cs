using System.Reflection;
using System.Reflection.Emit;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Runtime.Loader;
using HarmonyLib;
using HarmonyLib.Public.Patching;
using MonoMod.RuntimeDetour;
using MonoMod.RuntimeDetour.Platforms;
using MonoMod.Utils;

DetourHelper.Runtime = new DetourRuntimeNETCorePlatform();
MethodInfo target = typeof(ProbeTarget).GetMethod(
    nameof(ProbeTarget.AddOne),
    BindingFlags.Static | BindingFlags.NonPublic)
    ?? throw new InvalidOperationException("Harmony probe target was not found.");
MethodInfo postfix = typeof(ProbeTarget).GetMethod(
    nameof(ProbeTarget.DoubleResult),
    BindingFlags.Static | BindingFlags.NonPublic)
    ?? throw new InvalidOperationException("Harmony probe postfix was not found.");

new Harmony("LemonLoader.HarmonyCoreClrProbe").Patch(
    target,
    postfix: new HarmonyMethod(postfix));
if ((int)(target.Invoke(null, [2]) ?? -1) != 6)
    throw new InvalidOperationException("Harmony did not apply the CoreCLR probe patch.");

ResolverPrecedenceProbe.Run();
DynamicDelegateProbe.Run();

Console.WriteLine("HARMONY_CORECLR_PROBE_PASS");

internal static class ProbeTarget
{
    [MethodImpl(MethodImplOptions.NoInlining)]
    internal static int AddOne(int value) => value + 1;

    internal static void DoubleResult(ref int __result) => __result *= 2;

    internal static void ResolverTarget()
    {
    }
}

internal static class ResolverPrecedenceProbe
{
    internal static void Run()
    {
        MethodInfo resolverTarget = typeof(ProbeTarget).GetMethod(
            nameof(ProbeTarget.ResolverTarget),
            BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Harmony resolver probe target was not found.");
        MethodPatcher? expected = null;

        PatchManager.ClearAllPatcherResolvers();
        PatchManager.ResolvePatcher += (_, args) =>
        {
            expected = new ManagedMethodPatcher(args.Original);
            args.MethodPatcher = expected;
        };
        PatchManager.ResolvePatcher += ManagedMethodPatcher.TryResolve;
        PatchManager.ResolvePatcher += NativeDetourMethodPatcher.TryResolve;

        MethodPatcher actual = resolverTarget.GetMethodPatcher();
        if (expected is null || !ReferenceEquals(expected, actual))
            throw new InvalidOperationException("A default Harmony resolver replaced a selected patcher.");
    }
}

internal static class DynamicDelegateProbe
{
    internal static void Run()
    {
        var fixedAssembly = AssemblyBuilder.DefineDynamicAssembly(
            new AssemblyName("FixedSizeStructAssembly"),
            AssemblyBuilderAccess.Run);
        var fixedModule = fixedAssembly.DefineDynamicModule("FixedSizeStructAssembly");
        var typeBuilder = fixedModule.DefineType(
            "Fixed16",
            TypeAttributes.ExplicitLayout | TypeAttributes.Sealed,
            typeof(ValueType),
            16);
        for (var offset = 0; offset < 16; offset++)
        {
            var field = typeBuilder.DefineField(
                $"Byte{offset}",
                typeof(byte),
                FieldAttributes.Public);
            field.SetOffset(offset);
        }
        var fixedType = typeBuilder.CreateType();

        Assembly? ResolveDynamicAssembly(AssemblyLoadContext _, AssemblyName name) =>
            name.Name == fixedAssembly.GetName().Name ? fixedAssembly : null;

        AssemblyLoadContext.Default.Resolving += ResolveDynamicAssembly;
        try
        {
            using var dynamicMethod = new DynamicMethodDefinition(
                "DynamicDelegateProbe",
                typeof(void),
                [fixedType]);
            dynamicMethod.GetILGenerator().Emit(OpCodes.Ret);
            var generatedMethod = dynamicMethod.Generate();
            var delegateType = DelegateTypeFactory.instance.CreateDelegateType(
                generatedMethod,
                CallingConvention.Cdecl);
            _ = generatedMethod.CreateDelegate(delegateType);
        }
        finally
        {
            AssemblyLoadContext.Default.Resolving -= ResolveDynamicAssembly;
        }
    }
}

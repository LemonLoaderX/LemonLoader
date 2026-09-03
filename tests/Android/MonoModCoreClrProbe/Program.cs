using System.Reflection;
using MonoMod.RuntimeDetour;
using MonoMod.RuntimeDetour.Platforms;

DetourHelper.Runtime = new DetourRuntimeNETCorePlatform();
MethodInfo method = typeof(string).GetMethod(
    nameof(string.StartsWith),
    [typeof(string)])
    ?? throw new InvalidOperationException("Probe target was not found.");
if (DetourHelper.GetIdentifiable(method) is null)
    throw new InvalidOperationException("RuntimeDetour returned no identifiable method.");

Console.WriteLine("MONOMOD_CORECLR_PROBE_PASS");

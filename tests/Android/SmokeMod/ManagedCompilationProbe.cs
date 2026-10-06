using System.Reflection;
using System.Reflection.Emit;
using Mono.Cecil;
using Mono.Cecil.Cil;

namespace LemonLoader.Tests;

internal static class ManagedCompilationProbe
{
    internal static void Run()
    {
        var invalid = new DynamicMethod("InvalidIlFixture", typeof(int), Type.EmptyTypes);
        invalid.GetILGenerator().Emit(System.Reflection.Emit.OpCodes.Ret);
        try
        {
            invalid.CreateDelegate<Func<int>>()();
            throw new InvalidOperationException("Invalid IL was accepted.");
        }
        catch (InvalidProgramException) { }

        using var fixture = AssemblyDefinition.CreateAssembly(
            new AssemblyNameDefinition("MissingMethodFixture", new Version(1, 0)),
            "MissingMethodFixture", ModuleKind.Dll);
        var module = fixture.MainModule;
        var type = new TypeDefinition("Fixture", "Caller", Mono.Cecil.TypeAttributes.Public,
            module.ImportReference(typeof(object)));
        module.Types.Add(type);
        var call = new MethodDefinition("Call", Mono.Cecil.MethodAttributes.Public | Mono.Cecil.MethodAttributes.Static,
            module.TypeSystem.Void);
        type.Methods.Add(call);
        call.Body.Instructions.Add(Instruction.Create(Mono.Cecil.Cil.OpCodes.Call,
            new MethodReference("MissingMethodFixtureTarget", module.TypeSystem.Void, module.ImportReference(typeof(GC)))));
        call.Body.Instructions.Add(Instruction.Create(Mono.Cecil.Cil.OpCodes.Ret));
        using var output = new MemoryStream();
        fixture.Write(output);
        var loaded = Assembly.Load(output.ToArray());
        var invoke = loaded.GetType("Fixture.Caller", true)!.GetMethod("Call")!.CreateDelegate<Action>();
        try
        {
            invoke();
            throw new InvalidOperationException("The missing method was accepted.");
        }
        catch (MissingMethodException) { }
    }
}

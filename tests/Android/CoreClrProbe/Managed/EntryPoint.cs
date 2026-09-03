using System.Reflection;
using System.Reflection.Emit;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Threading;

namespace LemonLoader.CoreClrProbe;

public static class EntryPoint
{
    [UnmanagedCallersOnly]
    public static int Run() => RunCore();

    public static int RunDirect(nint marker)
    {
        if (marker == 0)
        {
            Console.Error.WriteLine("CORECLR_PROBE_FAIL native-argument=false");
            return 1;
        }
        return RunCore();
    }

    private static int RunCore()
    {
        try
        {
            Console.Error.WriteLine("CORECLR_PROBE_STAGE entry");
            var reflection = typeof(string).GetMethod(
                nameof(string.StartsWith),
                [typeof(string)]) is not null;
            Console.Error.WriteLine("CORECLR_PROBE_STAGE reflection");

            var dynamicMethod = new DynamicMethod(
                "ReturnProbeValue",
                typeof(int),
                Type.EmptyTypes,
                typeof(EntryPoint).Module);
            var generator = dynamicMethod.GetILGenerator();
            generator.Emit(OpCodes.Ldc_I4, 42);
            generator.Emit(OpCodes.Ret);
            var dynamicValue = ((Func<int>)dynamicMethod.CreateDelegate(typeof(Func<int>)))();
            Console.Error.WriteLine("CORECLR_PROBE_STAGE dynamic-method");

            using var threadPoolSignal = new ManualResetEventSlim();
            var threadPoolValue = 0;
            ThreadPool.QueueUserWorkItem(_ =>
            {
                threadPoolValue = 73;
                threadPoolSignal.Set();
            });
            var threadPool = threadPoolSignal.Wait(TimeSpan.FromSeconds(10)) &&
                threadPoolValue == 73;
            Console.Error.WriteLine("CORECLR_PROBE_STAGE thread-pool");

            var exception = false;
            try
            {
                ThrowProbeException();
            }
            catch (InvalidOperationException caught) when (caught.Message == "coreclr-probe")
            {
                exception = true;
            }
            Console.Error.WriteLine("CORECLR_PROBE_STAGE exception");

            var allocatedBefore = GC.GetTotalAllocatedBytes(true);
            _ = new byte[4 * 1024 * 1024];
            GC.Collect(2, GCCollectionMode.Forced, true, true);
            var gc = GC.GetTotalAllocatedBytes(true) > allocatedBefore;
            Console.Error.WriteLine("CORECLR_PROBE_STAGE gc");

            var runtime = NativeLibrary.Load("libcoreclr.so");
            var coreClrIdentity = NativeLibrary.TryGetExport(
                runtime,
                "coreclr_initialize",
                out _);
            var monoVmIdentity = NativeLibrary.TryGetExport(
                runtime,
                "monovm_initialize",
                out _);
            var maps = File.ReadAllText("/proc/self/maps");
            var mappedPrivateRuntime = maps.Contains(
                "/dotnet/shared/Microsoft.NETCore.App/",
                StringComparison.Ordinal) &&
                maps.Contains("/libcoreclr.so", StringComparison.Ordinal);
            Console.Error.WriteLine("CORECLR_PROBE_STAGE identity");

            if (!reflection || dynamicValue != 42 || !threadPool || !exception || !gc ||
                !coreClrIdentity || monoVmIdentity || !mappedPrivateRuntime)
            {
                Console.Error.WriteLine(
                    "CORECLR_PROBE_FAIL " +
                    $"reflection={reflection} dynamic={dynamicValue} threadPool={threadPool} " +
                    $"exception={exception} gc={gc} coreclr={coreClrIdentity} " +
                    $"monovm={monoVmIdentity} maps={mappedPrivateRuntime}");
                return 1;
            }

            Console.WriteLine(
                "CORECLR_PROBE_PASS reflection=true dynamic=42 threadPool=true " +
                "exception=true gc=true coreclr=true monovm=false maps=true");
            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine($"CORECLR_PROBE_EXCEPTION {exception}");
            return 1;
        }
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void ThrowProbeException() =>
        throw new InvalidOperationException("coreclr-probe");
}

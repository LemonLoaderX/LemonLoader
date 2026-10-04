using System.Runtime.InteropServices;

namespace LemonLoader.Tests.JniLibraries;

internal static unsafe class Host
{
    [StructLayout(LayoutKind.Sequential)]
    private struct VmArguments
    {
        public int Version;
        public int OptionCount;
        public nint Options;
        public byte IgnoreUnrecognized;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct VmOption { public nint Text; public nint Extra; }

    public static int Main(string[] args)
    {
        if (args.Length != 2)
        {
            Console.Error.WriteLine("Usage: Host <baseline|java-interop|jnet> <absolute JVM library path>");
            return 2;
        }
        // Own the host VM independently of the candidate. Candidates only borrow it.
        nint library = NativeLibrary.Load(args[1]);
        var create = (delegate* unmanaged<nint*, nint*, VmArguments*, int>)NativeLibrary.GetExport(library, "JNI_CreateJavaVM");
        nint checkedJni = Marshal.StringToHGlobalAnsi("-Xcheck:jni");
        VmOption option = new() { Text = checkedJni };
        VmArguments configuration = new() { Version = 0x10006, OptionCount = 1, Options = (nint)(&option) };
        nint vm = 0, env = 0;
        int result = create(&vm, &env, &configuration);
        Marshal.FreeHGlobal(checkedJni);
        if (result != 0) throw new InvalidOperationException($"JNI_CreateJavaVM: {result}");
        try
        {
            Suites.Run(args[0], vm, env, Console.WriteLine);
            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(exception);
            return 1;
        }
        finally
        {
            var destroy = (delegate* unmanaged<nint, int>)(*(nint**)vm)[3];
            if (destroy(vm) != 0) Console.Error.WriteLine("DestroyJavaVM failed.");
            // The JVM cannot safely be unloaded from a live CLR process.
        }
    }
}

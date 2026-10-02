using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text.Json;

if (args is ["evidence", var directoryPath, var processId])
{
    var reports = Directory.GetFiles(directoryPath, $"report-*-{processId}.crashreport.json*");
    if (reports.Length != 1)
        throw new Exception("No report attempt from the P/Invoke crashing process");
    var complete = reports[0].EndsWith(".json", StringComparison.Ordinal);
    if (complete && new FileInfo(reports[0]).Length == 0) throw new Exception("Empty completed report");
    Console.WriteLine(complete ? "PASS P/Invoke report completed" :
        new FileInfo(reports[0]).Length > 0 ? "LIMIT P/Invoke report is incomplete; retain partial bytes" :
        "LIMIT P/Invoke report failed before writing bytes; this reporter provides no trace");
    return;
}

if (args.Length is 4 or 6 && args[0] == "check")
{
    var directory = args[1];
    var files = Directory.Exists(directory)
        ? Directory.GetFiles(directory, "*.crashreport.json") : [];
    if (files.Length < int.Parse(args[2]) || files.Length > int.Parse(args[3]))
        throw new Exception($"Unexpected report count: {files.Length}");
    var sawCurrentCrash = args.Length == 4;
    foreach (var file in files)
    {
        using var document = JsonDocument.Parse(File.ReadAllText(file));
        if (document.RootElement.GetProperty("payload").GetProperty("threads").GetArrayLength() == 0)
            throw new Exception("Crash report has no thread context");
        if (document.RootElement.GetProperty("parameters").GetProperty("signal").GetString() is not ("6" or "11"))
            throw new Exception("Unexpected crash signal");
        if (args.Length == 6 && document.RootElement.GetProperty("payload").GetProperty("pid").GetString() == args[5] &&
            document.RootElement.GetProperty("parameters").GetProperty("signal").GetString() == args[4])
            sawCurrentCrash = true;
    }
    if (!sawCurrentCrash) throw new Exception("The current crashing process did not produce a report");
    Console.WriteLine($"PASS report JSON, thread context and retention ({files.Length} files)");
    return;
}

switch (args.Single())
{
    case "handled":
        try { Probe.Read(null!); }
        catch (NullReferenceException) { Console.WriteLine("PASS handled managed null access"); return; }
        throw new Exception("Expected null reference exception");
    case "failfast":
        Environment.FailFast("Crash report subprocess regression");
        break;
    case "native":
        Probe.CrashNativeThread();
        throw new Exception("Expected native fault");
    case "pinvoke":
        Probe.Memset(IntPtr.Zero, 1, 16);
        throw new Exception("Expected native fault");
    default: throw new ArgumentException("Unknown probe mode");
}

static class Probe
{
    internal sealed class Value { public int Number = 1; }
    [MethodImpl(MethodImplOptions.NoInlining)]
    internal static int Read(Value value) => value.Number;
    [DllImport("libc", EntryPoint = "memset")]
    internal static extern IntPtr Memset(IntPtr destination, int value, nuint count);
    [DllImport("libcrash-fixture.so", EntryPoint = "crash_native_thread")]
    internal static extern void CrashNativeThread();
}

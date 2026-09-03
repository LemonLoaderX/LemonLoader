#if ANDROID
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;

namespace MelonLoader.Utils
{
    internal static class AndroidThreadResourceDiagnostics
    {
        private static int _logged;

        internal static bool IsThreadCreationFailure(Exception exception)
        {
            for (Exception current = exception; current != null; current = current.InnerException)
            {
                if (current is OutOfMemoryException &&
                    current.StackTrace?.IndexOf(
                        "System.Threading.Thread.StartCore",
                        StringComparison.Ordinal) >= 0)
                    return true;
            }
            return false;
        }

        internal static void LogOnce(string context)
        {
            if (Interlocked.CompareExchange(ref _logged, 1, 0) != 0)
                return;

            try
            {
                string status = ReadSelectedLines(
                    "/proc/self/status",
                    "Threads:",
                    "VmPeak:",
                    "VmSize:",
                    "VmRSS:",
                    "VmData:",
                    "VmStk:",
                    "VmPTE:",
                    "VmSwap:");
                string limits = ReadSelectedLines(
                    "/proc/self/limits",
                    "Max processes",
                    "Max stack size",
                    "Max address space");
                string kernelLimits = ReadNamedValues(
                    ("threads-max", "/proc/sys/kernel/threads-max"),
                    ("pid_max", "/proc/sys/kernel/pid_max"));
                string cgroups = ReadCompactFile("/proc/self/cgroup");

                MelonLogger.Error(
                    $"[ThreadResource] Native thread creation failed during {context}. " +
                    $"pid={Environment.ProcessId}; status={status}; limits={limits}; " +
                    $"kernel={kernelLimits}; cgroup={cgroups}");
            }
            catch (Exception exception)
            {
                MelonLogger.Error(
                    $"[ThreadResource] Native thread creation failed during {context}; " +
                    $"resource snapshot failed: {exception.GetType().Name}: {exception.Message}");
            }
        }

        private static string ReadSelectedLines(string path, params string[] prefixes)
        {
            if (!File.Exists(path))
                return "unavailable";

            var values = new List<string>();
            foreach (string line in File.ReadLines(path))
            {
                string prefix = prefixes.FirstOrDefault(
                    candidate => line.StartsWith(candidate, StringComparison.Ordinal));
                if (prefix == null)
                    continue;

                string value = line.Substring(prefix.Length).Trim();
                values.Add(prefix.TrimEnd(':').Replace(' ', '_') + '=' + value);
            }
            return values.Count == 0 ? "unavailable" : string.Join(",", values);
        }

        private static string ReadNamedValues(params (string Name, string Path)[] files)
        {
            return string.Join(
                ",",
                files.Select(file =>
                    file.Name + '=' +
                    (File.Exists(file.Path) ? File.ReadAllText(file.Path).Trim() : "unavailable")));
        }

        private static string ReadCompactFile(string path)
        {
            return File.Exists(path)
                ? File.ReadAllText(path).Trim().Replace('\r', '|').Replace('\n', '|')
                : "unavailable";
        }
    }
}
#endif

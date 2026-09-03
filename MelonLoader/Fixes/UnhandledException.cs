using System;

namespace MelonLoader.Fixes
{
	internal static class UnhandledException
	{
		internal static void Install(AppDomain domain) =>
			domain.UnhandledException +=
				(sender, args) => Log(args.ExceptionObject);

		private static void Log(object exceptionObject)
		{
			try
			{
				string message = exceptionObject is Exception exception
					? exception.ToString()
					: exceptionObject?.ToString() ?? "Unknown non-Exception object";
#if ANDROID
				if (exceptionObject is Exception androidException &&
					MelonLoader.Utils.AndroidThreadResourceDiagnostics.IsThreadCreationFailure(
						androidException))
					MelonLoader.Utils.AndroidThreadResourceDiagnostics.LogOnce(
						"unhandled managed exception");
#endif
				MelonLogger.Error("Unhandled managed exception:\n" + message);
			}
			catch
			{
				// An exception logger must not replace the original fatal exception.
			}
		}
	}
}

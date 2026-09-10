// Isolate preference persistence from Unity, native logging and asynchronous file watching.
namespace MelonLoader
{
    public class MelonEvent<T>
    {
        private event Action<T> Handlers;
        public void Subscribe(Action<T> handler) => Handlers += handler;
        public void Invoke(T value) => Handlers?.Invoke(value);
    }

    public class MelonEvent<T, U>
    {
        private event Action<T, U> Handlers;
        public void Subscribe(Action<T, U> handler) => Handlers += handler;
        public void Invoke(T first, U second) => Handlers?.Invoke(first, second);
    }

    public static class MelonLogger
    {
        internal static readonly List<string> Messages = new();
        public static void Msg(string message) => Messages.Add(message);
        public static void MsgDirect(string message) => Msg(message);
        public static void Warning(string message) => Msg(message);
        public static void Error(string message) => Msg(message);
    }
}

namespace MelonLoader.Utils
{
    public static class MelonEnvironment
    {
        public static string UserDataDirectory { get; } = Path.Combine(
            AppContext.BaseDirectory, "runs", Guid.NewGuid().ToString("N"));
    }
}

namespace MelonLoader.Preferences
{
    public class TomlMapper { }
}

namespace MelonLoader.Preferences.IO
{
    internal class Watcher
    {
        internal Watcher(File file) { }
        internal void Destroy() { }
    }
}

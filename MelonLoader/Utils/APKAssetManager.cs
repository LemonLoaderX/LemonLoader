#if ANDROID
#nullable enable
using MelonLoader.Android;
using Java.Interop;
using System;
using System.IO;

namespace MelonLoader.Utils;

public static class APKAssetManager
{
    private static AndroidAssetManager? manager;
    public static void Initialize()
    {
        if (manager != null) return;
        using var thread = AndroidJava.AttachCurrentThread();
        using var activity = UnityPlayer.CurrentActivity ?? throw new InvalidOperationException("Unity Activity is unavailable.");
        manager = activity.Assets;
    }

    public static Stream? GetAssetStream(string path)
    {
        using var thread = AndroidJava.AttachCurrentThread();
        try { return new APKAssetStream((manager ?? throw new InvalidOperationException("AssetManager is not initialized.")).Open(path)); }
        catch (JavaException e)
        {
            string? type = JniEnvironment.Types.GetJniTypeNameFromInstance(e.PeerReference);
            e.Dispose();
            if (type == "java/io/FileNotFoundException") return null;
            throw new IOException("Android asset open failed: " + path, e);
        }
    }

    public static string[] GetDirectoryContents(string directory)
    {
        using var thread = AndroidJava.AttachCurrentThread();
        try { return (manager ?? throw new InvalidOperationException("AssetManager is not initialized.")).List(directory); }
        catch (JavaException e) { e.Dispose(); throw new IOException("Android asset listing failed: " + directory, e); }
    }

    public static bool DoesAssetExist(string path)
    {
        int separator = path.LastIndexOf('/');
        string directory = separator >= 0 ? path.Substring(0, separator) : "";
        string file = separator >= 0 ? path.Substring(separator + 1) : path;
        return Array.IndexOf(GetDirectoryContents(directory), file) >= 0;
    }

    public static byte[] GetAssetBytes(string path)
    {
        using var input = GetAssetStream(path);
        if (input == null) return [];
        using var output = new MemoryStream();
        input.CopyTo(output);
        return output.ToArray();
    }

    public static void SaveItemToDirectory(string itemPath, string copyBase, bool includeInitial = true)
    {
        string[] contents = GetDirectoryContents(itemPath);
        if (contents.Length != 0)
        {
            foreach (string item in contents) SaveItemToDirectory(itemPath + "/" + item, copyBase, includeInitial);
            return;
        }
        string path = includeInitial ? itemPath : itemPath.Substring(itemPath.IndexOf('/') + 1);
        if (path.Length == 0) return;
        string output = Path.Combine(copyBase, path);
        Directory.CreateDirectory(Path.GetDirectoryName(output)!);
        using var input = GetAssetStream(itemPath) ?? throw new FileNotFoundException("APK asset missing.", itemPath);
        using var file = File.Create(output);
        input.CopyTo(file);
    }

    /// <summary>Takes ownership of an InputStream peer and closes it deterministically.</summary>
    public sealed class APKAssetStream : Stream
    {
        private readonly JavaInputStream input;
        private readonly bool canSeek;
        private readonly long length;
        private JavaSByteArray? buffer;
        private int bufferCapacity;
        private long position;
        private bool disposed;

        public APKAssetStream(JavaInputStream input)
        {
            this.input = input ?? throw new ArgumentNullException(nameof(input));
            try
            {
                using var thread = AndroidJava.AttachCurrentThread();
                length = input.Available;
                canSeek = input.MarkSupported;
                if (canSeek) input.Mark(int.MaxValue);
            }
            catch (JavaException e) { input.Dispose(); e.Dispose(); throw new IOException("Android stream initialization failed.", e); }
            catch { input.Dispose(); throw; }
        }
        public override bool CanRead => !disposed;
        public override bool CanSeek => !disposed && canSeek;
        public override bool CanWrite => false;
        public override long Length => length;
        public override long Position { get => position; set => Seek(value, SeekOrigin.Begin); }

        public override int Read(byte[] destination, int offset, int count)
        {
            ArgumentNullException.ThrowIfNull(destination);
            ArgumentOutOfRangeException.ThrowIfNegative(offset);
            ArgumentOutOfRangeException.ThrowIfNegative(count);
            if (offset > destination.Length - count) throw new ArgumentException("Offset and count exceed the buffer length.");
            return Read(destination.AsSpan(offset, count));
        }

        public override unsafe int Read(Span<byte> destination)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            if (destination.IsEmpty) return 0;
            using var thread = AndroidJava.AttachCurrentThread();
            try
            {
                int count = Math.Min(destination.Length, 64 * 1024);
                if (bufferCapacity < count)
                {
                    var replacement = new JavaSByteArray(count);
                    buffer?.Dispose();
                    buffer = replacement;
                    bufferCapacity = count;
                }
                int read = input.Read(buffer!, 0, count);
                if (read == -1) return 0;
                if (read < 0 || read > count) throw new IOException("Android stream returned an invalid byte count.");
                fixed (byte* output = destination) JniEnvironment.Arrays.GetByteArrayRegion(buffer!.PeerReference, 0, read, (sbyte*)output);
                position += read;
                return read;
            }
            catch (JavaException e) { e.Dispose(); throw new IOException("Android asset read failed.", e); }
        }

        public override long Seek(long offset, SeekOrigin origin)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            if (!canSeek) throw new NotSupportedException("Android stream does not support seeking.");
            long target = origin switch
            {
                SeekOrigin.Begin => offset, SeekOrigin.Current => checked(position + offset),
                SeekOrigin.End => checked(length + offset), _ => throw new ArgumentOutOfRangeException(nameof(origin))
            };
            if (target < 0 || target > length) throw new IOException("Seek is outside the APK asset.");
            if (target == position) return position;
            using var thread = AndroidJava.AttachCurrentThread();
            try
            {
                if (target < position) { input.Reset(); position = 0; }
                while (position < target)
                {
                    long skipped = input.Skip(target - position);
                    if (skipped <= 0 || skipped > target - position) throw new IOException("Android stream could not reach the requested position.");
                    position += skipped;
                }
                return position;
            }
            catch (JavaException e) { e.Dispose(); throw new IOException("Android asset seek failed.", e); }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposed) return;
            disposed = true;
            try
            {
                if (disposing)
                {
                    using var thread = AndroidJava.AttachCurrentThread();
                    try { input.Close(); }
                    catch (JavaException e) { e.Dispose(); throw new IOException("Android asset close failed.", e); }
                    finally { try { input.Dispose(); } finally { buffer?.Dispose(); buffer = null; } }
                }
            }
            finally { base.Dispose(disposing); }
        }
        public override void Flush() { }
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
    }
}
#endif

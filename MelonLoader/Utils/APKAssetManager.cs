#if ANDROID
#nullable enable
using MelonLoader.Java;
using System;
using System.IO;

namespace MelonLoader.Utils;

public static class APKAssetManager
{
    private static JObject assetManager = null!;
    private static JMethodID openMethod, listMethod;

    public static void Initialize()
    {
        GetAndroidAssetManager();
    }

    public static void SaveItemToDirectory(string itemPath, string copyBase, bool includeInitial = true)
    {
        string[] contents = GetDirectoryContents(itemPath);
        if (contents.Length == 0)
        {
            string path = includeInitial ? itemPath : itemPath[(itemPath.IndexOf('/') + 1)..];
            if (string.IsNullOrEmpty(path))
                return;

            string outPath = Path.Combine(copyBase, path);
            string outDir = Path.GetDirectoryName(outPath)!;

            if (!Directory.Exists(outDir))
                Directory.CreateDirectory(outDir);

            using FileStream fileStream = File.Open(outPath, FileMode.Create);
            using Stream? assetStream = GetAssetStream(itemPath);
            if (assetStream == null)
                throw new Exception("[APKAssetManager] Failed to get asset stream: " + itemPath);

            byte[] buffer = new byte[81920];
            int bytesRead;
            while ((bytesRead = assetStream.Read(buffer, 0, buffer.Length)) > 0)
                fileStream.Write(buffer, 0, bytesRead);

            return;
        }

        foreach (string item in contents)
        {
            SaveItemToDirectory(Path.Combine(itemPath, item), copyBase, includeInitial);
        }
    }

    public static byte[] GetAssetBytes(string path)
    {
        using Stream? assetStream = GetAssetStream(path);
        if (assetStream == null)
            return [];

        using MemoryStream outputStream = new();
        assetStream.CopyTo(outputStream);
        return outputStream.ToArray();
    }

    public static Stream? GetAssetStream(string path)
    {
        using JString pathString = JNI.NewStringLocal(path);
        JObject asset;
        try
        {
            asset = JNI.CallObjectMethod<JObject>(assetManager, openMethod, new JValue(pathString));
        }
        catch (JThrowableException exception) when (exception.JavaClassName == "java.io.FileNotFoundException")
        { return null; }
        catch (JThrowableException exception) { throw new IOException("Android asset open failed: " + path, exception); }
        if (asset == null || !asset.Valid())
        {
            ClearException();
            return null;
        }

        ThrowIfException();

        try { return new APKAssetStream(asset); }
        catch { asset.Dispose(); throw; }
    }

    public static string[] GetDirectoryContents(string directory)
    {
        using JString pathString = JNI.NewStringLocal(directory);
        using JObjectArray<JString> assets = JNI.CallObjectMethod<JObjectArray<JString>>(assetManager, listMethod, new JValue(pathString));
        if (!assets.Valid())
        {
            ClearException();
            return [];
        }

        string[] cleanAssets = new string[assets.Length];
        for (int i = 0; i < cleanAssets.Length; i++)
        {
            using JString asset = assets[i];
            cleanAssets[i] = asset.GetString();
        }
        ThrowIfException();

        return cleanAssets;
    }

    public static bool DoesAssetExist(string path)
    {
        // using `list` isn't as fast as just calling open, but this allows the function to not crash on debuggable builds of apps
        int separatorIndex = path.LastIndexOf('/');
        string containingDir = separatorIndex >= 0 ? path[..separatorIndex] : string.Empty;
        string fileName = separatorIndex >= 0 ? path[(separatorIndex + 1)..] : path;
        using JString pathString = JNI.NewStringLocal(containingDir);
        using JObjectArray<JString> assets = JNI.CallObjectMethod<JObjectArray<JString>>(assetManager, listMethod, new JValue(pathString));
        if (!assets.Valid())
        {
            ClearException();
            return false;
        }

        bool exists = false;
        int length = assets.Length;
        for (int i = 0; i < length; i++)
        {
            using JString asset = assets[i];
            if (!string.Equals(fileName, asset.GetString(), StringComparison.Ordinal))
                continue;

            exists = true;
            break;
        }

        ThrowIfException();

        return exists;
    }

    private static void ClearException()
    {
        if (JNI.ExceptionCheck())
            JNI.ExceptionClear();
    }

    private static void ThrowIfException()
    {
        if (!JNI.ExceptionCheck())
            return;

        JNI.ExceptionDescribe();
        JNI.ExceptionClear();
        throw new IOException("An Android AssetManager operation failed.");
    }

    private static JMethodID RequiredMethod(JClass type, string name, string signature)
    {
        ThrowIfException();
        if (!type.Valid()) throw new IOException($"Android class is unavailable while resolving {name}{signature}.");
        JMethodID method;
        try { method = JNI.GetMethodID(type, name, signature); }
        catch (JThrowableException exception) { throw new IOException($"Required Android method is unavailable: {name}{signature}.", exception); }
        if (JNI.ExceptionCheck() || method.Handle == IntPtr.Zero)
        {
            ClearException();
            throw new IOException($"Required Android method is unavailable: {name}{signature}.");
        }
        return method;
    }

    private static void GetAndroidAssetManager()
    {
        if (assetManager?.Valid() ?? false)
            return;

        using JClass unityClass = JNI.FindClass("com/unity3d/player/UnityPlayer");
        JFieldID activityFieldId = JNI.GetStaticFieldID(unityClass, "currentActivity", "Landroid/app/Activity;");
        using JObject currentActivityObj = JNI.GetStaticObjectField<JObject>(unityClass, activityFieldId);
        using JClass activityClass = JNI.GetObjectClass(currentActivityObj);
        using JObject loader = JNI.CallObjectMethod<JObject>(currentActivityObj,
            activityClass.GetMethodID("getClassLoader", "()Ljava/lang/ClassLoader;"));
        JNI.SetApplicationClassLoader(loader);
        JObject assetManagerObj = JNI.CallObjectMethod<JObject>(currentActivityObj, JNI.GetMethodID(activityClass, "getAssets", "()Landroid/content/res/AssetManager;"));

        ThrowIfException();
        if (!assetManagerObj.Valid())
            throw new InvalidOperationException("Android AssetManager was not available.");

        using var managerClass = JNI.FindClass("android/content/res/AssetManager");
        openMethod = managerClass.GetMethodID("open", "(Ljava/lang/String;)Ljava/io/InputStream;");
        listMethod = managerClass.GetMethodID("list", "(Ljava/lang/String;)[Ljava/lang/String;");
        assetManager = assetManagerObj;
    }

    public class APKAssetStream : Stream, IDisposable
    {
        private readonly JMethodID _availableJmid;
        private readonly JMethodID _markJmid;
        private readonly JMethodID _markSupportedJmid;
        private readonly JMethodID _skipJmid;
        private readonly JMethodID _resetJmid;
        private readonly JMethodID _readJmid;
        private readonly JMethodID _closeJmid;

        private readonly JObject _streamObject;
        private readonly bool _canSeek;
        private readonly long _length;

        private long _pos = 0;
        private bool _disposed = false;
        private JArray<sbyte>? _readBuffer;
        private int _readBufferCapacity;

        public APKAssetStream(JObject obj)
        {
            _streamObject = obj;

            using JClass streamClass = JNI.FindClass("java/io/InputStream");

            _availableJmid = RequiredMethod(streamClass, "available", "()I");
            _readJmid = RequiredMethod(streamClass, "read", "([BII)I");
            _markJmid = RequiredMethod(streamClass, "mark", "(I)V");
            _markSupportedJmid = RequiredMethod(streamClass, "markSupported", "()Z");
            _skipJmid = RequiredMethod(streamClass, "skip", "(J)J");
            _resetJmid = RequiredMethod(streamClass, "reset", "()V");
            _closeJmid = RequiredMethod(streamClass, "close", "()V");

            _length = JNI.CallMethod<int>(_streamObject, _availableJmid);
            ThrowIfException();
            _canSeek = JNI.CallMethod<bool>(_streamObject, _markSupportedJmid);
            ThrowIfException();
            if (_canSeek)
                JNI.CallVoidMethod(_streamObject, _markJmid, new JValue(int.MaxValue));

            ThrowIfException();
        }

        public override bool CanRead => !_disposed;

        public override bool CanSeek => !_disposed && _canSeek;

        public override bool CanWrite => false;

        public override long Length => _length;

        public override long Position
        {
            get => _pos;
            set => Seek(value, SeekOrigin.Begin);
        }

        public override int Read(byte[] buffer, int offset, int count)
        {
            try { return ReadCore(buffer, offset, count); }
            catch (JThrowableException exception) { throw new IOException("Android asset read failed.", exception); }
        }

        private int ReadCore(byte[] buffer, int offset, int count)
        {
            if (_disposed)
                throw new ObjectDisposedException(nameof(APKAssetStream));
            if (buffer == null)
                throw new ArgumentNullException(nameof(buffer));
            if (offset < 0)
                throw new ArgumentOutOfRangeException(nameof(offset));
            if (count < 0)
                throw new ArgumentOutOfRangeException(nameof(count));
            if (buffer.Length - offset < count)
                throw new ArgumentException("Offset and count exceed the buffer length.");
            if (count == 0)
                return 0;

            int requested = Math.Min(count, 64 * 1024);
            if (_readBufferCapacity < requested)
            {
                var replacement = JNI.NewArray<sbyte>(requested);
                ThrowIfException();
                _readBuffer?.Dispose();
                _readBuffer = replacement;
                _readBufferCapacity = requested;
            }

            Span<JValue> arguments = stackalloc JValue[]
            {
                new JValue(_readBuffer!),
                new JValue(0),
                new JValue(requested)
            };
            int read = JNI.CallMethod<int>(_streamObject, _readJmid, arguments);
            ThrowIfException();

            if (read == -1)
                return 0;
            if (read < 0 || read > requested)
                throw new IOException("Android asset stream returned an invalid byte count.");
            JNI.CopyByteArrayRegion(_readBuffer!, buffer, offset, read);
            ThrowIfException();

            _pos += read;
            return read;
        }

        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();

        public override long Seek(long offset, SeekOrigin origin)
        {
            try { return SeekCore(offset, origin); }
            catch (JThrowableException exception) { throw new IOException("Android asset seek failed.", exception); }
        }

        private long SeekCore(long offset, SeekOrigin origin)
        {
            if (_disposed)
                throw new ObjectDisposedException(nameof(APKAssetStream));
            if (!_canSeek)
                throw new NotSupportedException("The APK asset stream does not support seeking.");

            long target = origin switch
            {
                SeekOrigin.Begin => offset,
                SeekOrigin.Current => checked(_pos + offset),
                SeekOrigin.End => checked(_length + offset),
                _ => throw new ArgumentOutOfRangeException(nameof(origin))
            };
            if (target < 0 || target > _length)
                throw new IOException("Attempted to seek outside the APK asset.");

            if (target == _pos) return _pos;
            if (target < _pos)
            {
                JNI.CallVoidMethod(_streamObject, _resetJmid);
                ThrowIfException();
                _pos = 0;
            }
            while (_pos < target)
            {
                long current = JNI.CallMethod<long>(
                    _streamObject,
                    _skipJmid,
                    new JValue(target - _pos));
                ThrowIfException();
                if (current <= 0 || current > target - _pos)
                    throw new IOException("The APK asset stream could not reach the requested position.");

                _pos += current;
            }

            ThrowIfException();
            _pos = target;
            return _pos;
        }

        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Flush() { }

        protected override void Dispose(bool disposing)
        {
            if (_disposed)
                return;
            _disposed = true;
            try
            {
                if (disposing)
                {
                    try
                    {
                        JNI.CallVoidMethod(_streamObject, _closeJmid);
                        ThrowIfException();
                    }
                    catch (JThrowableException exception) { throw new IOException("Android asset close failed.", exception); }
                    finally
                    {
                        try { _streamObject.Dispose(); }
                        finally
                        {
                            _readBuffer?.Dispose();
                            _readBuffer = null;
                        }
                    }
                }
            }
            finally { base.Dispose(disposing); }
        }
    }
}
#endif

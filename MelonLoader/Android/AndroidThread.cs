#if ANDROID
#nullable enable
using System;
using System.Threading;
using System.Threading.Tasks;

namespace MelonLoader.Android;

/// <summary>Dispatch managed work to Android's main thread and observe its completion.</summary>
public static class AndroidThread
{
    public static Task RunAsync(Action action, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(action);
        cancellationToken.ThrowIfCancellationRequested();
        using var thread = AndroidJava.AttachCurrentThread();
        using var activity = UnityPlayer.CurrentActivity ?? throw new InvalidOperationException("Unity Activity is unavailable.");
        var work = new UiWork(action);
        var callback = JavaCallbacks.Create<JavaRunnable>(new JavaCallbackMethod("run", (Action)work.Execute));
        work.Registration = callback;
        // An immediate UI invocation may dispose the registration before posting returns.
        try { activity.RunOnUiThread(callback.Peer); }
        catch { work.Release(); throw; }
        var cancellation = cancellationToken.Register(() => work.Cancel(cancellationToken));
        return Observe(work.Completion.Task, cancellation);
    }

    private static async Task Observe(Task task, CancellationTokenRegistration cancellation)
    { try { await task.ConfigureAwait(false); } finally { cancellation.Dispose(); } }

    internal sealed class UiWork
    {
        private const int Pending = 0, Running = 1, Finished = 2;
        private readonly Action action;
        private int state;
        internal readonly TaskCompletionSource Completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal JavaCallback<JavaRunnable>? Registration;
        internal UiWork(Action action) { this.action = action; }
        internal void Execute()
        {
            if (Interlocked.CompareExchange(ref state, Running, Pending) != Pending) return;
            try { action(); Completion.TrySetResult(); }
            catch (Exception exception) { Completion.TrySetException(exception); }
            finally { Interlocked.Exchange(ref state, Finished); Release(); }
        }
        internal void Cancel(CancellationToken token)
        {
            Completion.TrySetCanceled(token);
            if (Interlocked.CompareExchange(ref state, Finished, Pending) == Pending) Release();
        }
        internal void Release() => Interlocked.Exchange(ref Registration, null)?.Dispose();
    }
}
#endif

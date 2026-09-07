using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Text;

namespace LemonLoader.CoreClrProbe;

internal static class NetworkProbe
{
    internal static void Run()
    {
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        using var stop = new CancellationTokenSource(TimeSpan.FromSeconds(20));
        var server = ServeAsync(listener, stop.Token);
        try
        {
            var port = ((IPEndPoint)listener.LocalEndpoint).Port;
            var url = $"http://127.0.0.1:{port}/probe";
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
            if (client.GetStringAsync(url).GetAwaiter().GetResult() != "probe-ok")
                throw new InvalidOperationException("Async HTTP response mismatch");

            var syncRejected = false;
            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            try
            {
                using var response = client.Send(request);
                response.EnsureSuccessStatusCode();
                if (response.Content.ReadAsStringAsync().GetAwaiter().GetResult() != "probe-ok")
                    throw new InvalidOperationException("Sync HTTP response mismatch");
            }
            catch (PlatformNotSupportedException) { syncRejected = true; }
            var expectedRejection = Environment.GetEnvironmentVariable("LEMON_PROBE_EXPECT_SYNC_REJECTION") == "1";
            if (syncRejected != expectedRejection)
                throw new InvalidOperationException($"Sync HTTP rejection={syncRejected}, expected={expectedRejection}");
            File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "network-result.txt"),
                $"NETWORK_PROBE_PASS async=true syncRejected={syncRejected} transport=loopback-http");
        }
        finally
        {
            stop.Cancel();
            listener.Stop();
            try { server.GetAwaiter().GetResult(); }
            catch (OperationCanceledException) when (stop.IsCancellationRequested) { }
            catch (SocketException) when (stop.IsCancellationRequested) { }
        }
    }

    private static async Task ServeAsync(TcpListener listener, CancellationToken token)
    {
        var bytes = Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Length: 8\r\nConnection: close\r\n\r\nprobe-ok");
        while (!token.IsCancellationRequested)
        {
            using var peer = await listener.AcceptTcpClientAsync(token);
            using var stream = peer.GetStream();
            using var reader = new StreamReader(stream, Encoding.ASCII, false, 1024, true);
            while (await reader.ReadLineAsync(token) is { Length: > 0 }) { }
            await stream.WriteAsync(bytes, token);
        }
    }
}

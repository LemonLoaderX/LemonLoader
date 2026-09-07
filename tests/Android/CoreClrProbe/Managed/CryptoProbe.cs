using System.Net.Http;
using System.Security.Cryptography;

namespace LemonLoader.CoreClrProbe;

internal static class CryptoProbe
{
    internal static void Run()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "crypto-result.txt");
        File.WriteAllText(path, "CRYPTO_STAGE sha256\n");
        var digest = Convert.ToHexString(SHA256.HashData("abc"u8));
        if (digest != "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD")
            throw new InvalidOperationException("SHA256 known-answer mismatch");
        File.AppendAllText(path, "CRYPTO_STAGE rng\n");
        _ = RandomNumberGenerator.GetBytes(32);
        File.AppendAllText(path, "CRYPTO_STAGE rsa\n");
        using var rsa = RSA.Create(2048);
        var signature = rsa.SignData("probe"u8.ToArray(), HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        if (!rsa.VerifyData("probe"u8.ToArray(), signature, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1))
            throw new InvalidOperationException("RSA roundtrip failed");
        File.AppendAllText(path, "CRYPTO_PASS\n");
        var url = Environment.GetEnvironmentVariable("LEMON_PROBE_HTTPS_URL");
        if (!string.IsNullOrEmpty(url))
        {
            File.AppendAllText(path, "HTTPS_STAGE request\n");
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
            using var response = client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead).GetAwaiter().GetResult();
            response.EnsureSuccessStatusCode();
            File.AppendAllText(path, "HTTPS_PASS default-certificate-validation=true\n");
        }
    }
}

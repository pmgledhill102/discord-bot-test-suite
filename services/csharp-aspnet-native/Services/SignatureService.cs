// Ed25519 signature validation service.
// Uses NSec.Cryptography which is AOT-compatible (libsodium P/Invoke).

using NSec.Cryptography;

namespace DiscordWebhookNative.Services;

public class SignatureService
{
    private readonly PublicKey _publicKey;

    public SignatureService(string publicKeyHex)
    {
        var publicKeyBytes = Convert.FromHexString(publicKeyHex);
        _publicKey = PublicKey.Import(
            SignatureAlgorithm.Ed25519,
            publicKeyBytes,
            KeyBlobFormat.RawPublicKey);
    }

    /// <summary>
    /// Validates the Discord Ed25519 signature.
    /// </summary>
    /// <param name="signature">X-Signature-Ed25519 header value (hex encoded)</param>
    /// <param name="timestamp">X-Signature-Timestamp header value</param>
    /// <param name="body">Raw request body bytes</param>
    /// <returns>True if signature is valid</returns>
    public bool ValidateSignature(string? signature, string? timestamp, byte[] body)
    {
        if (string.IsNullOrEmpty(signature) || string.IsNullOrEmpty(timestamp))
        {
            return false;
        }

        // Decode signature from hex
        byte[] sigBytes;
        try
        {
            sigBytes = Convert.FromHexString(signature);
        }
        catch
        {
            return false;
        }

        if (sigBytes.Length != 64)
        {
            return false;
        }

        // Check timestamp (must be within 5 seconds)
        if (!long.TryParse(timestamp, out var ts))
        {
            return false;
        }

        var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        if (now - ts > 5)
        {
            return false;
        }

        // Verify signature: sign(timestamp + body)
        var timestampBytes = System.Text.Encoding.UTF8.GetBytes(timestamp);
        var message = new byte[timestampBytes.Length + body.Length];
        timestampBytes.CopyTo(message, 0);
        body.CopyTo(message, timestampBytes.Length);

        try
        {
            return SignatureAlgorithm.Ed25519.Verify(_publicKey, message, sigBytes);
        }
        catch
        {
            return false;
        }
    }
}

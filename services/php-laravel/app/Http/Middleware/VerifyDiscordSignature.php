<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class VerifyDiscordSignature
{
    private ?string $publicKey = null;

    public function __construct()
    {
        $publicKeyHex = env('DISCORD_PUBLIC_KEY');
        if ($publicKeyHex) {
            $this->publicKey = hex2bin($publicKeyHex);
        }
    }

    public function handle(Request $request, Closure $next): Response
    {
        if (! $this->publicKey) {
            return response()->json(['error' => 'server configuration error'], 500);
        }

        $signature = $request->header('X-Signature-Ed25519', '');
        $timestamp = $request->header('X-Signature-Timestamp', '');

        if (empty($signature) || empty($timestamp)) {
            return response()->json(['error' => 'invalid signature'], 401);
        }

        // Check timestamp (must be within 5 seconds)
        $ts = filter_var($timestamp, FILTER_VALIDATE_INT);
        if ($ts === false || time() - $ts > 5) {
            return response()->json(['error' => 'invalid signature'], 401);
        }

        // Decode signature
        $signatureBytes = @hex2bin($signature);
        if ($signatureBytes === false || strlen($signatureBytes) !== SODIUM_CRYPTO_SIGN_BYTES) {
            return response()->json(['error' => 'invalid signature'], 401);
        }

        // Get raw body
        $body = $request->getContent();

        // Verify signature: verify(timestamp + body)
        $message = $timestamp.$body;
        if (! sodium_crypto_sign_verify_detached($signatureBytes, $message, $this->publicKey)) {
            return response()->json(['error' => 'invalid signature'], 401);
        }

        return $next($request);
    }
}

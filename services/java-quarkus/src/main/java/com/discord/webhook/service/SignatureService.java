package com.discord.webhook.service;

import io.quarkus.runtime.Startup;
import jakarta.annotation.PostConstruct;
import jakarta.enterprise.context.ApplicationScoped;
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters;
import org.bouncycastle.crypto.signers.Ed25519Signer;
import org.bouncycastle.util.encoders.Hex;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

import java.nio.charset.StandardCharsets;
import java.time.Instant;

@ApplicationScoped
@Startup
public class SignatureService {

    private static final Logger logger = Logger.getLogger(SignatureService.class);
    private static final long TIMESTAMP_TOLERANCE_SECONDS = 5;

    @ConfigProperty(name = "discord.public-key")
    String publicKeyHex;

    private Ed25519PublicKeyParameters publicKey;

    @PostConstruct
    public void init() {
        if (publicKeyHex == null || publicKeyHex.isEmpty()) {
            throw new IllegalStateException("DISCORD_PUBLIC_KEY environment variable is required");
        }

        try {
            byte[] publicKeyBytes = Hex.decode(publicKeyHex);
            publicKey = new Ed25519PublicKeyParameters(publicKeyBytes, 0);
            logger.info("Discord public key initialized");
        } catch (Exception e) {
            throw new IllegalStateException("Invalid DISCORD_PUBLIC_KEY: " + e.getMessage(), e);
        }
    }

    public boolean validateSignature(String signature, String timestamp, byte[] body) {
        if (signature == null || signature.isEmpty() || timestamp == null || timestamp.isEmpty()) {
            return false;
        }

        // Decode signature from hex
        byte[] signatureBytes;
        try {
            signatureBytes = Hex.decode(signature);
        } catch (Exception e) {
            logger.debug("Invalid hex signature: " + e.getMessage());
            return false;
        }

        // Parse and validate timestamp
        long ts;
        try {
            ts = Long.parseLong(timestamp);
        } catch (NumberFormatException e) {
            logger.debug("Invalid timestamp format: " + timestamp);
            return false;
        }

        long now = Instant.now().getEpochSecond();
        if (now - ts > TIMESTAMP_TOLERANCE_SECONDS) {
            logger.debug("Timestamp expired: " + ts + " (now: " + now + ")");
            return false;
        }

        // Verify signature: sign(timestamp + body)
        try {
            byte[] timestampBytes = timestamp.getBytes(StandardCharsets.UTF_8);
            byte[] message = new byte[timestampBytes.length + body.length];
            System.arraycopy(timestampBytes, 0, message, 0, timestampBytes.length);
            System.arraycopy(body, 0, message, timestampBytes.length, body.length);

            Ed25519Signer verifier = new Ed25519Signer();
            verifier.init(false, publicKey);
            verifier.update(message, 0, message.length);
            return verifier.verifySignature(signatureBytes);
        } catch (Exception e) {
            logger.debug("Signature verification failed: " + e.getMessage());
            return false;
        }
    }
}

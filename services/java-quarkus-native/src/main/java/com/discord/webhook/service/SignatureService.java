package com.discord.webhook.service;

import io.quarkus.runtime.Startup;
import jakarta.annotation.PostConstruct;
import jakarta.enterprise.context.ApplicationScoped;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.PublicKey;
import java.security.Signature;
import java.security.spec.EdECPoint;
import java.security.spec.EdECPublicKeySpec;
import java.security.spec.NamedParameterSpec;
import java.time.Instant;

@ApplicationScoped
@Startup
public class SignatureService {

    private static final Logger logger = Logger.getLogger(SignatureService.class);
    private static final long TIMESTAMP_TOLERANCE_SECONDS = 5;

    @ConfigProperty(name = "discord.public-key")
    String publicKeyHex;

    private PublicKey publicKey;

    @PostConstruct
    public void init() {
        if (publicKeyHex == null || publicKeyHex.isEmpty()) {
            throw new IllegalStateException("DISCORD_PUBLIC_KEY environment variable is required");
        }

        try {
            byte[] publicKeyBytes = hexToBytes(publicKeyHex);
            publicKey = parseEd25519PublicKey(publicKeyBytes);
            logger.info("Discord public key initialized (using Java native Ed25519)");
        } catch (Exception e) {
            throw new IllegalStateException("Invalid DISCORD_PUBLIC_KEY: " + e.getMessage(), e);
        }
    }

    private PublicKey parseEd25519PublicKey(byte[] publicKeyBytes) throws Exception {
        // Ed25519 public keys are 32 bytes
        if (publicKeyBytes.length != 32) {
            throw new IllegalArgumentException("Invalid Ed25519 public key length: " + publicKeyBytes.length);
        }

        // Reverse the bytes (Ed25519 uses little-endian)
        byte[] reversed = new byte[32];
        for (int i = 0; i < 32; i++) {
            reversed[i] = publicKeyBytes[31 - i];
        }

        // Check the sign bit (MSB of the last byte of the original key)
        boolean xOdd = (publicKeyBytes[31] & 0x80) != 0;

        // Clear the sign bit for the y coordinate
        reversed[0] &= 0x7F;

        // Create the EdECPoint
        EdECPoint point = new EdECPoint(xOdd, new java.math.BigInteger(1, reversed));

        // Create the key spec
        EdECPublicKeySpec keySpec = new EdECPublicKeySpec(NamedParameterSpec.ED25519, point);

        // Generate the public key
        KeyFactory keyFactory = KeyFactory.getInstance("Ed25519");
        return keyFactory.generatePublic(keySpec);
    }

    public boolean validateSignature(String signature, String timestamp, byte[] body) {
        if (signature == null || signature.isEmpty() || timestamp == null || timestamp.isEmpty()) {
            return false;
        }

        // Decode signature from hex
        byte[] signatureBytes;
        try {
            signatureBytes = hexToBytes(signature);
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

            Signature verifier = Signature.getInstance("Ed25519");
            verifier.initVerify(publicKey);
            verifier.update(message);
            return verifier.verify(signatureBytes);
        } catch (Exception e) {
            logger.debug("Signature verification failed: " + e.getMessage());
            return false;
        }
    }

    private static byte[] hexToBytes(String hex) {
        int len = hex.length();
        byte[] data = new byte[len / 2];
        for (int i = 0; i < len; i += 2) {
            data[i / 2] = (byte) ((Character.digit(hex.charAt(i), 16) << 4)
                    + Character.digit(hex.charAt(i + 1), 16));
        }
        return data;
    }
}

package com.discord.webhook.service;

import jakarta.annotation.PostConstruct;
import jakarta.enterprise.context.ApplicationScoped;
import java.security.KeyFactory;
import java.security.PublicKey;
import java.security.Signature;
import java.security.spec.EdECPoint;
import java.security.spec.EdECPublicKeySpec;
import java.security.spec.NamedParameterSpec;
import java.util.Optional;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

@ApplicationScoped
public class SignatureService {

  private static final Logger logger = Logger.getLogger(SignatureService.class);

  @ConfigProperty(name = "discord.public.key")
  Optional<String> publicKeyHex;

  private PublicKey publicKey;

  @PostConstruct
  public void init() {
    if (publicKeyHex.isEmpty() || publicKeyHex.get().isEmpty()) {
      logger.warn("Discord public key not configured");
      return;
    }

    try {
      byte[] keyBytes = hexToBytes(publicKeyHex.get());
      publicKey = decodeEd25519PublicKey(keyBytes);
      logger.info("Ed25519 public key loaded successfully (Java native crypto)");
    } catch (Exception e) {
      logger.error("Failed to load Ed25519 public key: " + e.getMessage());
    }
  }

  public boolean verifySignature(String signature, String timestamp, String body) {
    if (publicKey == null) {
      logger.warn("Cannot verify signature: public key not loaded");
      return false;
    }

    // Validate timestamp is not too old (5 second window per Discord spec)
    try {
      long timestampSeconds = Long.parseLong(timestamp);
      long currentSeconds = System.currentTimeMillis() / 1000;
      if (currentSeconds - timestampSeconds > 5) {
        logger.warn("Request timestamp is too old");
        return false;
      }
    } catch (NumberFormatException e) {
      logger.error("Invalid timestamp format: " + timestamp);
      return false;
    }

    try {
      byte[] signatureBytes = hexToBytes(signature);
      byte[] messageBytes = (timestamp + body).getBytes();

      Signature sig = Signature.getInstance("Ed25519");
      sig.initVerify(publicKey);
      sig.update(messageBytes);
      return sig.verify(signatureBytes);
    } catch (Exception e) {
      logger.error("Signature verification failed: " + e.getMessage());
      return false;
    }
  }

  private PublicKey decodeEd25519PublicKey(byte[] keyBytes) throws Exception {
    // Ed25519 public keys are 32 bytes
    if (keyBytes.length != 32) {
      throw new IllegalArgumentException("Invalid Ed25519 public key length: " + keyBytes.length);
    }

    // Reverse the bytes (Ed25519 uses little-endian)
    byte[] reversed = new byte[keyBytes.length];
    for (int i = 0; i < keyBytes.length; i++) {
      reversed[i] = keyBytes[keyBytes.length - 1 - i];
    }

    // Check the sign bit (MSB of the last byte in original, first in reversed)
    boolean xOdd = (reversed[0] & 0x80) != 0;
    reversed[0] &= 0x7F; // Clear the sign bit

    // Create BigInteger for y coordinate
    java.math.BigInteger y = new java.math.BigInteger(1, reversed);

    // Create the EdEC point and key spec
    EdECPoint point = new EdECPoint(xOdd, y);
    NamedParameterSpec paramSpec = new NamedParameterSpec("Ed25519");
    EdECPublicKeySpec keySpec = new EdECPublicKeySpec(paramSpec, point);

    // Generate the public key
    KeyFactory keyFactory = KeyFactory.getInstance("EdDSA");
    return keyFactory.generatePublic(keySpec);
  }

  private byte[] hexToBytes(String hex) {
    int len = hex.length();
    byte[] data = new byte[len / 2];
    for (int i = 0; i < len; i += 2) {
      data[i / 2] =
          (byte)
              ((Character.digit(hex.charAt(i), 16) << 4) + Character.digit(hex.charAt(i + 1), 16));
    }
    return data;
  }
}

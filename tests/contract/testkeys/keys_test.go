package testkeys

import (
	"crypto/ed25519"
	"encoding/hex"
	"testing"
)

func TestKeyPairIsValid(t *testing.T) {
	// Verify the key pair is valid by signing and verifying a message
	message := []byte("test message")
	signature := ed25519.Sign(TestPrivateKey, message)

	if !ed25519.Verify(TestPublicKey, message, signature) {
		t.Error("signature verification failed")
	}
}

func TestKeyPairIsDeterministic(t *testing.T) {
	// The public key should always be the same value
	// This test documents the expected public key for services to use
	expectedPublicKey := "398803f0f03317b6dc57069dbe7820e5f6cf7d5ff43ad6219710b19b0b49c159"

	if TestPublicKeyHex != expectedPublicKey {
		t.Errorf("public key changed!\ngot:  %s\nwant: %s", TestPublicKeyHex, expectedPublicKey)
	}
}

func TestSignRequest(t *testing.T) {
	body := []byte(`{"type":1}`)
	signature, timestamp := SignRequest(body)

	// Verify the signature is valid hex
	sigBytes, err := hex.DecodeString(signature)
	if err != nil {
		t.Fatalf("signature is not valid hex: %v", err)
	}

	// Verify signature length
	if len(sigBytes) != ed25519.SignatureSize {
		t.Errorf("signature length = %d, want %d", len(sigBytes), ed25519.SignatureSize)
	}

	// Verify the signature is actually valid
	message := append([]byte(timestamp), body...)
	if !ed25519.Verify(TestPublicKey, message, sigBytes) {
		t.Error("generated signature does not verify")
	}
}

func TestSignRequestWithTimestamp(t *testing.T) {
	body := []byte(`{"type":1}`)
	timestamp := "1234567890"
	signature := SignRequestWithTimestamp(body, timestamp)

	sigBytes, err := hex.DecodeString(signature)
	if err != nil {
		t.Fatalf("signature is not valid hex: %v", err)
	}

	message := append([]byte(timestamp), body...)
	if !ed25519.Verify(TestPublicKey, message, sigBytes) {
		t.Error("generated signature does not verify")
	}
}

func TestExpiredTimestamp(t *testing.T) {
	timestamp := ExpiredTimestamp()
	if timestamp == "" {
		t.Error("ExpiredTimestamp returned empty string")
	}
}

func TestInvalidSignature(t *testing.T) {
	sig := InvalidSignature()

	sigBytes, err := hex.DecodeString(sig)
	if err != nil {
		t.Fatalf("InvalidSignature is not valid hex: %v", err)
	}

	if len(sigBytes) != ed25519.SignatureSize {
		t.Errorf("InvalidSignature length = %d, want %d", len(sigBytes), ed25519.SignatureSize)
	}
}

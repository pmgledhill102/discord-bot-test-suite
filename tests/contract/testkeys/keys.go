// Package testkeys provides deterministic Ed25519 key pairs for contract testing.
//
// The keys are derived from a fixed seed to ensure reproducibility across test runs.
// Services under test must be configured with the TestPublicKeyHex value.
package testkeys

import (
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"time"
)

const (
	// testSeed is a fixed seed for deterministic key generation.
	// DO NOT use these keys in production - they are for testing only.
	testSeed = "discord-bot-test-suite-ed25519-test-key-seed-v1"
)

var (
	// TestPrivateKey is the Ed25519 private key for signing test requests.
	TestPrivateKey ed25519.PrivateKey

	// TestPublicKey is the Ed25519 public key for verifying signatures.
	TestPublicKey ed25519.PublicKey

	// TestPublicKeyHex is the hex-encoded public key for DISCORD_PUBLIC_KEY env var.
	TestPublicKeyHex string
)

func init() {
	// Derive a 32-byte seed from our fixed seed string
	seed := sha256.Sum256([]byte(testSeed))

	// Generate the key pair from the seed
	TestPrivateKey = ed25519.NewKeyFromSeed(seed[:])
	TestPublicKey = TestPrivateKey.Public().(ed25519.PublicKey)
	TestPublicKeyHex = hex.EncodeToString(TestPublicKey)
}

// SignRequest signs a Discord interaction request body with the test private key.
// Returns the signature and timestamp to use in request headers.
//
// Headers to set:
//   - X-Signature-Ed25519: signature (hex-encoded)
//   - X-Signature-Timestamp: timestamp
func SignRequest(body []byte) (signature string, timestamp string) {
	timestamp = fmt.Sprintf("%d", time.Now().Unix())
	return SignRequestWithTimestamp(body, timestamp), timestamp
}

// SignRequestWithTimestamp signs a request body with a specific timestamp.
// This is useful for testing expired timestamp scenarios.
func SignRequestWithTimestamp(body []byte, timestamp string) string {
	// Discord signature format: sign(timestamp + body)
	message := append([]byte(timestamp), body...)
	sig := ed25519.Sign(TestPrivateKey, message)
	return hex.EncodeToString(sig)
}

// ExpiredTimestamp returns a timestamp that is older than Discord's 5-second tolerance.
func ExpiredTimestamp() string {
	return fmt.Sprintf("%d", time.Now().Add(-10*time.Second).Unix())
}

// InvalidSignature returns a syntactically valid but incorrect signature.
func InvalidSignature() string {
	// Return a valid hex string of the right length but wrong value
	return hex.EncodeToString(make([]byte, ed25519.SignatureSize))
}

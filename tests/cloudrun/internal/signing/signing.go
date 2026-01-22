// Package signing provides Ed25519 signing for Discord interaction requests.
//
// This package uses the same key derivation as tests/contract/testkeys to ensure
// compatibility with services configured for contract testing.
package signing

import (
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"time"
)

const (
	// testSeed is a fixed seed for deterministic key generation.
	// Must match the seed in tests/contract/testkeys/keys.go
	testSeed = "discord-bot-test-suite-ed25519-test-key-seed-v1"
)

// Signer provides methods for signing Discord interaction requests.
type Signer struct {
	privateKey ed25519.PrivateKey
	publicKey  ed25519.PublicKey
}

// NewSigner creates a new Signer using the test key pair.
func NewSigner() *Signer {
	// Derive a 32-byte seed from our fixed seed string
	seed := sha256.Sum256([]byte(testSeed))

	// Generate the key pair from the seed
	privateKey := ed25519.NewKeyFromSeed(seed[:])
	publicKey := privateKey.Public().(ed25519.PublicKey)

	return &Signer{
		privateKey: privateKey,
		publicKey:  publicKey,
	}
}

// PublicKeyHex returns the hex-encoded public key for DISCORD_PUBLIC_KEY env var.
func (s *Signer) PublicKeyHex() string {
	return hex.EncodeToString(s.publicKey)
}

// SignRequest signs a Discord interaction request body.
// Returns the signature (hex) and timestamp to use in request headers.
//
// Headers to set:
//   - X-Signature-Ed25519: signature
//   - X-Signature-Timestamp: timestamp
func (s *Signer) SignRequest(body []byte) (signature string, timestamp string) {
	timestamp = fmt.Sprintf("%d", time.Now().Unix())
	return s.SignRequestWithTimestamp(body, timestamp), timestamp
}

// SignRequestWithTimestamp signs a request body with a specific timestamp.
func (s *Signer) SignRequestWithTimestamp(body []byte, timestamp string) string {
	// Discord signature format: sign(timestamp + body)
	message := append([]byte(timestamp), body...)
	sig := ed25519.Sign(s.privateKey, message)
	return hex.EncodeToString(sig)
}

// DiscordPingRequest returns a valid Discord ping request body.
func DiscordPingRequest() []byte {
	return []byte(`{"type":1}`)
}

// DiscordSlashCommandRequest returns a valid Discord slash command request body.
// The command name and guild/channel/user IDs are test values.
func DiscordSlashCommandRequest() []byte {
	return []byte(`{
		"type": 2,
		"id": "123456789",
		"application_id": "987654321",
		"token": "test-token-redacted",
		"guild_id": "111222333",
		"channel_id": "444555666",
		"member": {
			"user": {
				"id": "777888999",
				"username": "testuser"
			}
		},
		"data": {
			"id": "cmd123",
			"name": "test",
			"type": 1
		}
	}`)
}

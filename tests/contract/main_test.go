// Package contract provides black-box contract tests for Discord webhook services.
//
// These tests validate service behavior via HTTP requests to containerized services.
// Tests do not inspect internal code—only external behavior matters.
package contract

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"testing"
	"time"

	"cloud.google.com/go/pubsub"

	"github.com/pmgledhill102/discord-bot-test-suite/tests/contract/testkeys"
)

var (
	// targetURL is the base URL of the service under test
	targetURL string

	// pubsubClient is the Pub/Sub client for verifying published messages
	pubsubClient *pubsub.Client

	// projectID is the GCP project ID for Pub/Sub
	projectID string
)

func TestMain(m *testing.M) {
	// Get target URL from environment
	targetURL = os.Getenv("CONTRACT_TEST_TARGET")
	if targetURL == "" {
		targetURL = "http://localhost:8080"
	}

	// Get project ID
	projectID = os.Getenv("GOOGLE_CLOUD_PROJECT")
	if projectID == "" {
		projectID = "test-project"
	}

	// Initialize Pub/Sub client if emulator is available
	if emulatorHost := os.Getenv("PUBSUB_EMULATOR_HOST"); emulatorHost != "" {
		ctx := context.Background()
		var err error
		pubsubClient, err = pubsub.NewClient(ctx, projectID)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Warning: Failed to create Pub/Sub client: %v\n", err)
		}
	}

	// Run tests
	code := m.Run()

	// Cleanup
	if pubsubClient != nil {
		pubsubClient.Close()
	}

	os.Exit(code)
}

// InteractionRequest represents a Discord interaction request
type InteractionRequest struct {
	Type          int                    `json:"type"`
	ID            string                 `json:"id,omitempty"`
	ApplicationID string                 `json:"application_id,omitempty"`
	Token         string                 `json:"token,omitempty"`
	Data          map[string]interface{} `json:"data,omitempty"`
	GuildID       string                 `json:"guild_id,omitempty"`
	ChannelID     string                 `json:"channel_id,omitempty"`
	Member        map[string]interface{} `json:"member,omitempty"`
	Locale        string                 `json:"locale,omitempty"`
}

// InteractionResponse represents a Discord interaction response
type InteractionResponse struct {
	Type int                    `json:"type"`
	Data map[string]interface{} `json:"data,omitempty"`
}

// sendRequest sends a signed request to the service under test
func sendRequest(t *testing.T, body []byte) (*http.Response, []byte) {
	t.Helper()
	signature, timestamp := testkeys.SignRequest(body)
	return sendRequestWithHeaders(t, body, signature, timestamp)
}

// sendRequestWithHeaders sends a request with custom signature headers
func sendRequestWithHeaders(t *testing.T, body []byte, signature, timestamp string) (*http.Response, []byte) {
	t.Helper()

	req, err := http.NewRequest("POST", targetURL, bytes.NewReader(body))
	if err != nil {
		t.Fatalf("Failed to create request: %v", err)
	}

	req.Header.Set("Content-Type", "application/json")
	if signature != "" {
		req.Header.Set("X-Signature-Ed25519", signature)
	}
	if timestamp != "" {
		req.Header.Set("X-Signature-Timestamp", timestamp)
	}

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("Request failed: %v", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("Failed to read response body: %v", err)
	}

	return resp, respBody
}

// createPingRequest creates a valid ping interaction request
func createPingRequest() InteractionRequest {
	return InteractionRequest{
		Type:          1, // Ping
		ID:            "test-interaction-id",
		ApplicationID: "test-app-id",
		Token:         "test-token",
	}
}

// createSlashCommandRequest creates a valid slash command interaction request
func createSlashCommandRequest(commandName string) InteractionRequest {
	return InteractionRequest{
		Type:          2, // Application Command
		ID:            fmt.Sprintf("test-interaction-%d", time.Now().UnixNano()),
		ApplicationID: "test-app-id",
		Token:         "sensitive-token-should-be-redacted",
		Data: map[string]interface{}{
			"id":   "cmd-id",
			"name": commandName,
		},
		GuildID:   "test-guild-id",
		ChannelID: "test-channel-id",
		Member: map[string]interface{}{
			"user": map[string]interface{}{
				"id":       "user-id",
				"username": "testuser",
			},
		},
		Locale: "en-US",
	}
}

// toJSON marshals a value to JSON bytes
func toJSON(t *testing.T, v interface{}) []byte {
	t.Helper()
	data, err := json.Marshal(v)
	if err != nil {
		t.Fatalf("Failed to marshal JSON: %v", err)
	}
	return data
}

// parseResponse parses a response body as InteractionResponse
func parseResponse(t *testing.T, body []byte) InteractionResponse {
	t.Helper()
	var resp InteractionResponse
	if err := json.Unmarshal(body, &resp); err != nil {
		t.Fatalf("Failed to parse response JSON: %v\nBody: %s", err, string(body))
	}
	return resp
}

// createTestTopic creates a unique topic for a test and returns cleanup function
func createTestTopic(t *testing.T) (*pubsub.Topic, func()) {
	t.Helper()

	if pubsubClient == nil {
		t.Skip("Pub/Sub emulator not available")
	}

	ctx := context.Background()
	topicName := fmt.Sprintf("test-topic-%d", time.Now().UnixNano())

	topic, err := pubsubClient.CreateTopic(ctx, topicName)
	if err != nil {
		t.Fatalf("Failed to create topic: %v", err)
	}

	cleanup := func() {
		topic.Stop()
		if err := topic.Delete(ctx); err != nil {
			t.Logf("Warning: Failed to delete topic: %v", err)
		}
	}

	return topic, cleanup
}

// createTestSubscription creates a subscription for a topic
func createTestSubscription(t *testing.T, topic *pubsub.Topic) (*pubsub.Subscription, func()) {
	t.Helper()

	ctx := context.Background()
	subName := fmt.Sprintf("test-sub-%d", time.Now().UnixNano())

	sub, err := pubsubClient.CreateSubscription(ctx, subName, pubsub.SubscriptionConfig{
		Topic:       topic,
		AckDeadline: 10 * time.Second,
	})
	if err != nil {
		t.Fatalf("Failed to create subscription: %v", err)
	}

	cleanup := func() {
		if err := sub.Delete(ctx); err != nil {
			t.Logf("Warning: Failed to delete subscription: %v", err)
		}
	}

	return sub, cleanup
}

// receiveMessage receives a single message from a subscription with timeout
func receiveMessage(t *testing.T, sub *pubsub.Subscription, timeout time.Duration) (*pubsub.Message, bool) {
	t.Helper()

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	var received *pubsub.Message
	err := sub.Receive(ctx, func(ctx context.Context, msg *pubsub.Message) {
		received = msg
		msg.Ack()
		cancel() // Stop receiving after first message
	})

	if err != nil && err != context.Canceled {
		t.Logf("Receive error: %v", err)
	}

	return received, received != nil
}

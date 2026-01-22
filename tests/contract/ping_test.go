package contract

import (
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestPing_ValidPing(t *testing.T) {
	req := createPingRequest()
	body := toJSON(t, req)

	resp, respBody := sendRequest(t, body)

	// Check status code
	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected status 200 OK, got %d", resp.StatusCode)
	}

	// Parse response
	response := parseResponse(t, respBody)

	// Check response type is Pong (type=1)
	if response.Type != 1 {
		t.Errorf("Expected response type 1 (Pong), got %d", response.Type)
	}
}

func TestPing_ResponseContentType(t *testing.T) {
	req := createPingRequest()
	body := toJSON(t, req)

	resp, _ := sendRequest(t, body)

	contentType := resp.Header.Get("Content-Type")
	if !strings.HasPrefix(contentType, "application/json") {
		t.Errorf("Expected Content-Type to start with application/json, got %s", contentType)
	}
}

func TestPing_DoesNotPublishToPubSub(t *testing.T) {
	if pubsubClient == nil {
		t.Skip("Pub/Sub emulator not available")
	}

	// Create a topic and subscription
	topic, cleanupTopic := createTestTopic(t)
	defer cleanupTopic()

	sub, cleanupSub := createTestSubscription(t, topic)
	defer cleanupSub()

	// Note: This test assumes the service is configured to publish to this topic.
	// In practice, we may need to configure the service with the topic name.
	// For now, we verify that after a ping, no message appears.

	// Send ping request
	req := createPingRequest()
	body := toJSON(t, req)

	resp, _ := sendRequest(t, body)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("Ping failed with status %d", resp.StatusCode)
	}

	// Wait briefly and check that no message was published
	msg, received := receiveMessage(t, sub, 2*time.Second)
	if received {
		t.Errorf("Ping should NOT publish to Pub/Sub, but received message: %s", string(msg.Data))
	}
}

func TestPing_MinimalRequest(t *testing.T) {
	// Test with minimal required fields
	req := InteractionRequest{
		Type: 1, // Ping - minimal required field
	}
	body := toJSON(t, req)

	resp, respBody := sendRequest(t, body)

	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected status 200 OK for minimal ping, got %d", resp.StatusCode)
	}

	response := parseResponse(t, respBody)
	if response.Type != 1 {
		t.Errorf("Expected response type 1 (Pong), got %d", response.Type)
	}
}

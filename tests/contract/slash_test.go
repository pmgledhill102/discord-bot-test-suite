package contract

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestSlashCommand_ValidCommand(t *testing.T) {
	req := createSlashCommandRequest("test-command")
	body := toJSON(t, req)

	resp, respBody := sendRequest(t, body)

	// Check status code
	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected status 200 OK, got %d", resp.StatusCode)
	}

	// Parse response
	response := parseResponse(t, respBody)

	// Check response type is Deferred (type=5)
	if response.Type != 5 {
		t.Errorf("Expected response type 5 (Deferred), got %d", response.Type)
	}
}

func TestSlashCommand_ResponseIsNonEphemeral(t *testing.T) {
	req := createSlashCommandRequest("test-command")
	body := toJSON(t, req)

	resp, respBody := sendRequest(t, body)

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("Request failed with status %d", resp.StatusCode)
	}

	// Parse full response to check for ephemeral flag
	var fullResponse map[string]interface{}
	if err := json.Unmarshal(respBody, &fullResponse); err != nil {
		t.Fatalf("Failed to parse response: %v", err)
	}

	// Check that flags field either doesn't exist or doesn't have ephemeral bit (64)
	if data, ok := fullResponse["data"].(map[string]interface{}); ok {
		if flags, ok := data["flags"].(float64); ok {
			if int(flags)&64 != 0 {
				t.Error("Response has ephemeral flag (64) set, but should be non-ephemeral")
			}
		}
	}
}

func TestSlashCommand_PublishesToPubSub(t *testing.T) {
	if pubsubClient == nil {
		t.Skip("Pub/Sub emulator not available")
	}

	// Create a topic and subscription
	topic, cleanupTopic := createTestTopic(t)
	defer cleanupTopic()

	sub, cleanupSub := createTestSubscription(t, topic) //nolint:staticcheck // Used after t.Skip
	defer cleanupSub()

	// Note: For this test to work, the service must be configured to publish
	// to our test topic. This may require environment variable configuration.
	// This test serves as a template for when the service is properly configured.

	t.Skip("Skipping: Service must be configured with test topic name")

	// Send slash command request
	req := createSlashCommandRequest("test-command")
	body := toJSON(t, req)

	resp, _ := sendRequest(t, body)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("Slash command failed with status %d", resp.StatusCode)
	}

	// Wait for message
	msg, received := receiveMessage(t, sub, 5*time.Second)
	if !received {
		t.Fatal("Expected Pub/Sub message for slash command, but none received")
	}

	// Verify message is valid JSON
	var msgData map[string]interface{}
	if err := json.Unmarshal(msg.Data, &msgData); err != nil {
		t.Errorf("Pub/Sub message is not valid JSON: %v", err)
	}
}

func TestSlashCommand_TokenRedactedFromPubSub(t *testing.T) {
	if pubsubClient == nil {
		t.Skip("Pub/Sub emulator not available")
	}

	// Create a topic and subscription
	topic, cleanupTopic := createTestTopic(t)
	defer cleanupTopic()

	sub, cleanupSub := createTestSubscription(t, topic) //nolint:staticcheck // Used after t.Skip
	defer cleanupSub()

	t.Skip("Skipping: Service must be configured with test topic name")

	// Send slash command with sensitive token
	req := createSlashCommandRequest("test-command")
	req.Token = "SUPER_SECRET_TOKEN_12345"
	body := toJSON(t, req)

	resp, _ := sendRequest(t, body)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("Slash command failed with status %d", resp.StatusCode)
	}

	// Wait for message
	msg, received := receiveMessage(t, sub, 5*time.Second)
	if !received {
		t.Fatal("Expected Pub/Sub message, but none received")
	}

	// Check that token is NOT in the message
	msgStr := string(msg.Data)
	if strings.Contains(msgStr, "SUPER_SECRET_TOKEN_12345") {
		t.Error("Pub/Sub message contains sensitive token - should be redacted!")
	}
	if strings.Contains(msgStr, "token") {
		// Parse to verify token field is actually present and not just the word "token"
		var msgData map[string]interface{}
		if err := json.Unmarshal(msg.Data, &msgData); err == nil {
			if _, hasToken := msgData["token"]; hasToken {
				t.Error("Pub/Sub message contains 'token' field - should be removed!")
			}
		}
	}
}

func TestSlashCommand_ResponseContentType(t *testing.T) {
	req := createSlashCommandRequest("test-command")
	body := toJSON(t, req)

	resp, _ := sendRequest(t, body)

	contentType := resp.Header.Get("Content-Type")
	if !strings.HasPrefix(contentType, "application/json") {
		t.Errorf("Expected Content-Type to start with application/json, got %s", contentType)
	}
}

func TestSlashCommand_WithOptions(t *testing.T) {
	req := createSlashCommandRequest("test-command")
	req.Data["options"] = []map[string]interface{}{
		{
			"name":  "option1",
			"type":  3, // String type
			"value": "test-value",
		},
	}
	body := toJSON(t, req)

	resp, respBody := sendRequest(t, body)

	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected status 200 OK, got %d", resp.StatusCode)
	}

	response := parseResponse(t, respBody)
	if response.Type != 5 {
		t.Errorf("Expected response type 5 (Deferred), got %d", response.Type)
	}
}

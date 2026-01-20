package contract

import (
	"net/http"
	"testing"
)

func TestError_MalformedJSON(t *testing.T) {
	body := []byte(`{not valid json}`)

	resp, _ := sendRequest(t, body)

	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("Expected status 400 Bad Request for malformed JSON, got %d", resp.StatusCode)
	}
}

func TestError_EmptyBody(t *testing.T) {
	body := []byte(``)

	resp, _ := sendRequest(t, body)

	// Empty body should be rejected (either 400 or 401 depending on implementation)
	if resp.StatusCode != http.StatusBadRequest && resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("Expected status 400 or 401 for empty body, got %d", resp.StatusCode)
	}
}

func TestError_MissingTypeField(t *testing.T) {
	// JSON object without required 'type' field
	body := []byte(`{"id": "test-id", "application_id": "test-app"}`)

	resp, _ := sendRequest(t, body)

	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("Expected status 400 Bad Request for missing type field, got %d", resp.StatusCode)
	}
}

func TestError_UnknownInteractionType(t *testing.T) {
	req := InteractionRequest{
		Type:          99, // Unknown type
		ID:            "test-id",
		ApplicationID: "test-app",
	}
	body := toJSON(t, req)

	resp, _ := sendRequest(t, body)

	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("Expected status 400 Bad Request for unknown interaction type, got %d", resp.StatusCode)
	}
}

func TestError_InvalidTypeValue(t *testing.T) {
	// Type field with invalid value (string instead of int)
	body := []byte(`{"type": "invalid"}`)

	resp, _ := sendRequest(t, body)

	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("Expected status 400 Bad Request for invalid type value, got %d", resp.StatusCode)
	}
}

func TestError_NullBody(t *testing.T) {
	body := []byte(`null`)

	resp, _ := sendRequest(t, body)

	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("Expected status 400 Bad Request for null body, got %d", resp.StatusCode)
	}
}

func TestError_ArrayBody(t *testing.T) {
	// JSON array instead of object
	body := []byte(`[{"type": 1}]`)

	resp, _ := sendRequest(t, body)

	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("Expected status 400 Bad Request for array body, got %d", resp.StatusCode)
	}
}

func TestError_NegativeType(t *testing.T) {
	req := InteractionRequest{
		Type: -1,
	}
	body := toJSON(t, req)

	resp, _ := sendRequest(t, body)

	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("Expected status 400 Bad Request for negative type, got %d", resp.StatusCode)
	}
}

func TestError_ZeroType(t *testing.T) {
	req := InteractionRequest{
		Type: 0,
	}
	body := toJSON(t, req)

	resp, _ := sendRequest(t, body)

	// Type 0 is not a valid Discord interaction type
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("Expected status 400 Bad Request for type 0, got %d", resp.StatusCode)
	}
}

func TestError_UnsupportedInteractionType3(t *testing.T) {
	// Type 3 is Message Component, which we don't support
	req := InteractionRequest{
		Type:          3,
		ID:            "test-id",
		ApplicationID: "test-app",
	}
	body := toJSON(t, req)

	resp, _ := sendRequest(t, body)

	// Should return 400 for unsupported type
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("Expected status 400 Bad Request for unsupported type 3, got %d", resp.StatusCode)
	}
}

func TestError_UnsupportedInteractionType4(t *testing.T) {
	// Type 4 is Application Command Autocomplete, which we don't support
	req := InteractionRequest{
		Type:          4,
		ID:            "test-id",
		ApplicationID: "test-app",
	}
	body := toJSON(t, req)

	resp, _ := sendRequest(t, body)

	// Should return 400 for unsupported type
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("Expected status 400 Bad Request for unsupported type 4, got %d", resp.StatusCode)
	}
}

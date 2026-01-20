package contract

import (
	"net/http"
	"testing"

	"github.com/pmgledhill102/discord-bot-test-suite/tests/contract/testkeys"
)

func TestSignature_ValidSignature(t *testing.T) {
	req := createPingRequest()
	body := toJSON(t, req)

	resp, _ := sendRequest(t, body)

	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected status 200 OK, got %d", resp.StatusCode)
	}
}

func TestSignature_MissingSignatureHeader(t *testing.T) {
	req := createPingRequest()
	body := toJSON(t, req)

	// Send with timestamp but no signature
	_, timestamp := testkeys.SignRequest(body)
	resp, _ := sendRequestWithHeaders(t, body, "", timestamp)

	if resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("Expected status 401 Unauthorized for missing signature, got %d", resp.StatusCode)
	}
}

func TestSignature_MissingTimestampHeader(t *testing.T) {
	req := createPingRequest()
	body := toJSON(t, req)

	// Send with signature but no timestamp
	signature, _ := testkeys.SignRequest(body)
	resp, _ := sendRequestWithHeaders(t, body, signature, "")

	if resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("Expected status 401 Unauthorized for missing timestamp, got %d", resp.StatusCode)
	}
}

func TestSignature_InvalidSignature(t *testing.T) {
	req := createPingRequest()
	body := toJSON(t, req)

	// Send with invalid signature
	_, timestamp := testkeys.SignRequest(body)
	invalidSig := testkeys.InvalidSignature()
	resp, _ := sendRequestWithHeaders(t, body, invalidSig, timestamp)

	if resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("Expected status 401 Unauthorized for invalid signature, got %d", resp.StatusCode)
	}
}

func TestSignature_ExpiredTimestamp(t *testing.T) {
	req := createPingRequest()
	body := toJSON(t, req)

	// Send with expired timestamp (> 5 seconds old)
	expiredTimestamp := testkeys.ExpiredTimestamp()
	signature := testkeys.SignRequestWithTimestamp(body, expiredTimestamp)
	resp, _ := sendRequestWithHeaders(t, body, signature, expiredTimestamp)

	if resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("Expected status 401 Unauthorized for expired timestamp, got %d", resp.StatusCode)
	}
}

func TestSignature_MalformedSignatureHex(t *testing.T) {
	req := createPingRequest()
	body := toJSON(t, req)

	// Send with malformed hex signature
	_, timestamp := testkeys.SignRequest(body)
	resp, _ := sendRequestWithHeaders(t, body, "not-valid-hex!", timestamp)

	if resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("Expected status 401 Unauthorized for malformed signature hex, got %d", resp.StatusCode)
	}
}

func TestSignature_WrongBodySigned(t *testing.T) {
	req := createPingRequest()
	body := toJSON(t, req)

	// Sign a different body
	differentBody := []byte(`{"type":1,"id":"different"}`)
	signature, timestamp := testkeys.SignRequest(differentBody)

	// Send with mismatched signature
	resp, _ := sendRequestWithHeaders(t, body, signature, timestamp)

	if resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("Expected status 401 Unauthorized for mismatched body, got %d", resp.StatusCode)
	}
}

// Package gcp provides clients for interacting with GCP services.
package gcp

import (
	"context"
	"fmt"

	"google.golang.org/api/idtoken"
	"google.golang.org/api/option"
	"google.golang.org/api/run/v2"
)

// ClientOptions returns common client options for GCP API clients.
// Uses Application Default Credentials (ADC).
func ClientOptions() []option.ClientOption {
	return []option.ClientOption{
		// ADC is used by default, no explicit options needed
	}
}

// NewRunService creates a new Cloud Run API service client.
func NewRunService(ctx context.Context) (*run.Service, error) {
	svc, err := run.NewService(ctx, ClientOptions()...)
	if err != nil {
		return nil, fmt.Errorf("creating Cloud Run service: %w", err)
	}
	return svc, nil
}

// GetIDToken fetches an ID token for the target audience (service URL).
// Uses the default service account credentials.
// The token source automatically caches and refreshes tokens.
func GetIDToken(ctx context.Context, audience string) (string, error) {
	tokenSource, err := idtoken.NewTokenSource(ctx, audience)
	if err != nil {
		return "", fmt.Errorf("creating token source: %w", err)
	}

	token, err := tokenSource.Token()
	if err != nil {
		return "", fmt.Errorf("fetching token: %w", err)
	}

	return token.AccessToken, nil
}

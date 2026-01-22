package gcp

import (
	"context"
	"fmt"
	"time"

	"cloud.google.com/go/logging/logadmin"
	"google.golang.org/api/iterator"
)

// LoggingClient provides methods for querying Cloud Logging.
type LoggingClient struct {
	client    *logadmin.Client
	projectID string
}

// NewLoggingClient creates a new Cloud Logging client.
func NewLoggingClient(ctx context.Context, projectID string) (*LoggingClient, error) {
	client, err := logadmin.NewClient(ctx, projectID)
	if err != nil {
		return nil, fmt.Errorf("creating logging client: %w", err)
	}

	return &LoggingClient{
		client:    client,
		projectID: projectID,
	}, nil
}

// Close closes the logging client.
func (c *LoggingClient) Close() error {
	return c.client.Close()
}

// ContainerStartupMetrics contains timing information from Cloud Run startup.
type ContainerStartupMetrics struct {
	// InstanceStartTime is when the container instance started
	InstanceStartTime time.Time
	// ContainerStartupLatency is the time to start the container (from Cloud Run logs)
	ContainerStartupLatency time.Duration
	// FirstRequestTime is when the first request was received
	FirstRequestTime time.Time
	// Found indicates if startup metrics were found in logs
	Found bool
}

// GetContainerStartupMetrics retrieves container startup timing from Cloud Logging.
// It looks for Cloud Run system logs that indicate container startup.
func (c *LoggingClient) GetContainerStartupMetrics(ctx context.Context, serviceName, region string, after time.Time) (*ContainerStartupMetrics, error) {
	// Build filter for Cloud Run startup logs
	// Cloud Run logs container startup in the run.googleapis.com/requests log
	filter := fmt.Sprintf(`
		resource.type="cloud_run_revision"
		resource.labels.service_name="%s"
		resource.labels.location="%s"
		timestamp >= "%s"
		textPayload:"Container started"
	`, serviceName, region, after.Format(time.RFC3339))

	metrics := &ContainerStartupMetrics{}

	it := c.client.Entries(ctx, logadmin.Filter(filter))
	for {
		entry, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("reading log entries: %w", err)
		}

		metrics.Found = true
		metrics.InstanceStartTime = entry.Timestamp

		// Try to extract startup latency from the log payload
		// Cloud Run logs typically include timing information
		if payload, ok := entry.Payload.(string); ok {
			// Parse "Container started in X.XXs" format
			var seconds float64
			if _, err := fmt.Sscanf(payload, "Container started in %fs", &seconds); err == nil {
				metrics.ContainerStartupLatency = time.Duration(seconds * float64(time.Second))
			}
		}

		// We only need the first (most recent) entry
		break
	}

	return metrics, nil
}

// GetRequestLatencyFromLogs retrieves request latency information from Cloud Run logs.
func (c *LoggingClient) GetRequestLatencyFromLogs(ctx context.Context, serviceName, region string, after time.Time) (time.Duration, error) {
	// Build filter for request logs
	filter := fmt.Sprintf(`
		resource.type="cloud_run_revision"
		resource.labels.service_name="%s"
		resource.labels.location="%s"
		timestamp >= "%s"
		httpRequest.requestMethod="POST"
	`, serviceName, region, after.Format(time.RFC3339))

	it := c.client.Entries(ctx, logadmin.Filter(filter))
	for {
		entry, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return 0, fmt.Errorf("reading log entries: %w", err)
		}

		// Extract latency from httpRequest if available
		if entry.HTTPRequest != nil && entry.HTTPRequest.Latency > 0 {
			return entry.HTTPRequest.Latency, nil
		}

		// We only need the first entry
		break
	}

	return 0, fmt.Errorf("no request latency found in logs")
}

// WaitForStartupLog waits for the container startup log to appear.
func (c *LoggingClient) WaitForStartupLog(ctx context.Context, serviceName, region string, startTime time.Time, timeout time.Duration) (*ContainerStartupMetrics, error) {
	deadline := time.Now().Add(timeout)

	for time.Now().Before(deadline) {
		metrics, err := c.GetContainerStartupMetrics(ctx, serviceName, region, startTime)
		if err != nil {
			return nil, err
		}

		if metrics.Found {
			return metrics, nil
		}

		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(2 * time.Second):
			continue
		}
	}

	return nil, fmt.Errorf("timeout waiting for startup log")
}

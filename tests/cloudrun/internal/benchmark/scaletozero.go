// Package benchmark provides cold start and warm request benchmarking for Cloud Run services.
package benchmark

import (
	"context"
	"fmt"
	"time"

	"google.golang.org/api/monitoring/v3"
)

// ScaleToZeroConfig contains configuration for scale-to-zero detection.
type ScaleToZeroConfig struct {
	ProjectID   string
	Region      string
	ServiceName string
	Timeout     time.Duration
	PollInterval time.Duration
}

// WaitForScaleToZero waits until the Cloud Run service has zero instances.
// It uses the Cloud Monitoring API to check instance count.
func WaitForScaleToZero(ctx context.Context, cfg ScaleToZeroConfig) error {
	if cfg.Timeout == 0 {
		cfg.Timeout = 15 * time.Minute
	}
	if cfg.PollInterval == 0 {
		cfg.PollInterval = 30 * time.Second
	}

	deadline := time.Now().Add(cfg.Timeout)

	// Create monitoring client
	monitoringService, err := monitoring.NewService(ctx)
	if err != nil {
		return fmt.Errorf("creating monitoring service: %w", err)
	}

	for time.Now().Before(deadline) {
		count, err := getInstanceCount(ctx, monitoringService, cfg)
		if err != nil {
			// Log error but continue polling
			fmt.Printf("Warning: error checking instance count: %v\n", err)
		} else if count == 0 {
			return nil // Service has scaled to zero
		} else {
			fmt.Printf("Waiting for scale to zero: %d instances active\n", count)
		}

		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(cfg.PollInterval):
			continue
		}
	}

	return fmt.Errorf("timeout waiting for service %s to scale to zero", cfg.ServiceName)
}

// getInstanceCount queries Cloud Monitoring for the current instance count.
func getInstanceCount(ctx context.Context, svc *monitoring.Service, cfg ScaleToZeroConfig) (int64, error) {
	// Build the filter for Cloud Run instance count metric
	filter := fmt.Sprintf(`
		resource.type="cloud_run_revision" AND
		resource.labels.service_name="%s" AND
		resource.labels.location="%s" AND
		metric.type="run.googleapis.com/container/instance_count"
	`, cfg.ServiceName, cfg.Region)

	// Query the last 5 minutes of data
	now := time.Now()
	interval := &monitoring.TimeInterval{
		StartTime: now.Add(-5 * time.Minute).Format(time.RFC3339),
		EndTime:   now.Format(time.RFC3339),
	}

	req := svc.Projects.TimeSeries.List(fmt.Sprintf("projects/%s", cfg.ProjectID)).
		Filter(filter).
		IntervalStartTime(interval.StartTime).
		IntervalEndTime(interval.EndTime).
		AggregationAlignmentPeriod("60s").
		AggregationPerSeriesAligner("ALIGN_MEAN")

	resp, err := req.Context(ctx).Do()
	if err != nil {
		return -1, fmt.Errorf("querying metrics: %w", err)
	}

	// Sum up instance counts from all revisions
	var totalInstances int64
	for _, ts := range resp.TimeSeries {
		if len(ts.Points) > 0 {
			// Get the most recent point
			point := ts.Points[0]
			if point.Value.Int64Value != nil {
				totalInstances += *point.Value.Int64Value
			} else if point.Value.DoubleValue != nil {
				totalInstances += int64(*point.Value.DoubleValue)
			}
		}
	}

	return totalInstances, nil
}

// IsScaledToZero checks if the service currently has zero instances.
func IsScaledToZero(ctx context.Context, cfg ScaleToZeroConfig) (bool, error) {
	monitoringService, err := monitoring.NewService(ctx)
	if err != nil {
		return false, fmt.Errorf("creating monitoring service: %w", err)
	}

	count, err := getInstanceCount(ctx, monitoringService, cfg)
	if err != nil {
		return false, err
	}

	return count == 0, nil
}

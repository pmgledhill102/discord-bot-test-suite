package benchmark

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"sort"
	"time"

	"github.com/pmgledhill102/discord-bot-test-suite/tests/cloudrun/internal/gcp"
	"github.com/pmgledhill102/discord-bot-test-suite/tests/cloudrun/internal/signing"
)

// ColdStartResult contains the results of a single cold start measurement.
type ColdStartResult struct {
	// TTFB is time to first byte from request start
	TTFB time.Duration
	// TotalLatency is the total request duration
	TotalLatency time.Duration
	// ContainerStartup is the container startup time from Cloud Logging (if available)
	ContainerStartup time.Duration
	// StatusCode is the HTTP response status code
	StatusCode int
	// Timestamp is when the measurement was taken
	Timestamp time.Time
	// Error if the request failed
	Error error
}

// ColdStartStats contains aggregated statistics from multiple cold start measurements.
type ColdStartStats struct {
	// Individual results
	Results []ColdStartResult

	// TTFB statistics
	TTFBMin time.Duration
	TTFBMax time.Duration
	TTFBAvg time.Duration
	TTFBP50 time.Duration
	TTFBP95 time.Duration
	TTFBP99 time.Duration

	// Container startup statistics (from Cloud Logging)
	ContainerStartupMin time.Duration
	ContainerStartupMax time.Duration
	ContainerStartupAvg time.Duration

	// Success/failure counts
	SuccessCount int
	FailureCount int
}

// ColdStartConfig contains configuration for cold start benchmarking.
type ColdStartConfig struct {
	ServiceURL         string
	ServiceName        string
	ProjectID          string
	Region             string
	Iterations         int
	ScaleToZeroTimeout time.Duration
	Signer             *signing.Signer
	LoggingClient      *gcp.LoggingClient
}

// MeasureColdStart performs a single cold start measurement.
// It sends a signed Discord ping request and measures the response time.
func MeasureColdStart(ctx context.Context, serviceURL string, signer *signing.Signer) (*ColdStartResult, error) {
	result := &ColdStartResult{
		Timestamp: time.Now(),
	}

	// Create the ping request body
	body := signing.DiscordPingRequest()
	signature, timestamp := signer.SignRequest(body)

	// Create the HTTP request
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, serviceURL, bytes.NewReader(body))
	if err != nil {
		result.Error = fmt.Errorf("creating request: %w", err)
		return result, result.Error
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Signature-Ed25519", signature)
	req.Header.Set("X-Signature-Timestamp", timestamp)

	// Measure the request
	client := &http.Client{
		Timeout: 30 * time.Second,
	}

	start := time.Now()
	resp, err := client.Do(req)
	if err != nil {
		result.Error = fmt.Errorf("making request: %w", err)
		result.TotalLatency = time.Since(start)
		return result, result.Error
	}
	defer resp.Body.Close()

	// Read the response body to complete the request
	_, _ = io.ReadAll(resp.Body)

	result.TotalLatency = time.Since(start)
	result.TTFB = result.TotalLatency // For now, TTFB approximates total latency
	result.StatusCode = resp.StatusCode

	if resp.StatusCode != http.StatusOK {
		result.Error = fmt.Errorf("unexpected status code: %d", resp.StatusCode)
	}

	return result, nil
}

// RunColdStartBenchmark runs multiple cold start iterations with scale-to-zero waits.
func RunColdStartBenchmark(ctx context.Context, cfg ColdStartConfig) (*ColdStartStats, error) {
	if cfg.Iterations == 0 {
		cfg.Iterations = 5
	}
	if cfg.ScaleToZeroTimeout == 0 {
		cfg.ScaleToZeroTimeout = 15 * time.Minute
	}

	stats := &ColdStartStats{
		Results: make([]ColdStartResult, 0, cfg.Iterations),
	}

	for i := 0; i < cfg.Iterations; i++ {
		fmt.Printf("Cold start iteration %d/%d\n", i+1, cfg.Iterations)

		// Skip scale-to-zero wait on first iteration (service might already be cold)
		if i > 0 {
			fmt.Println("  Waiting for scale to zero...")
			scaleConfig := ScaleToZeroConfig{
				ProjectID:   cfg.ProjectID,
				Region:      cfg.Region,
				ServiceName: cfg.ServiceName,
				Timeout:     cfg.ScaleToZeroTimeout,
			}

			if err := WaitForScaleToZero(ctx, scaleConfig); err != nil {
				return nil, fmt.Errorf("waiting for scale to zero: %w", err)
			}
		}

		// Record the time before making the request (for log queries)
		requestStartTime := time.Now()

		// Measure cold start
		fmt.Println("  Measuring cold start...")
		result, err := MeasureColdStart(ctx, cfg.ServiceURL, cfg.Signer)
		if err != nil {
			fmt.Printf("  Warning: cold start measurement failed: %v\n", err)
			stats.FailureCount++
		} else {
			stats.SuccessCount++
			fmt.Printf("  TTFB: %v\n", result.TTFB)
		}

		// Try to get container startup time from Cloud Logging
		if cfg.LoggingClient != nil && result.Error == nil {
			metrics, err := cfg.LoggingClient.WaitForStartupLog(
				ctx,
				cfg.ServiceName,
				cfg.Region,
				requestStartTime,
				30*time.Second,
			)
			if err == nil && metrics.Found {
				result.ContainerStartup = metrics.ContainerStartupLatency
				fmt.Printf("  Container startup: %v\n", result.ContainerStartup)
			}
		}

		stats.Results = append(stats.Results, *result)
	}

	// Calculate statistics
	stats.CalculateStats()

	return stats, nil
}

// CalculateStats computes aggregate statistics from individual results.
func (s *ColdStartStats) CalculateStats() {
	if len(s.Results) == 0 {
		return
	}

	// Collect successful TTFB values
	var ttfbs []time.Duration
	var startups []time.Duration
	var ttfbSum time.Duration
	var startupSum time.Duration

	for _, r := range s.Results {
		if r.Error == nil {
			ttfbs = append(ttfbs, r.TTFB)
			ttfbSum += r.TTFB

			if r.ContainerStartup > 0 {
				startups = append(startups, r.ContainerStartup)
				startupSum += r.ContainerStartup
			}
		}
	}

	if len(ttfbs) == 0 {
		return
	}

	// Sort for percentile calculations
	sort.Slice(ttfbs, func(i, j int) bool { return ttfbs[i] < ttfbs[j] })

	// TTFB stats
	s.TTFBMin = ttfbs[0]
	s.TTFBMax = ttfbs[len(ttfbs)-1]
	s.TTFBAvg = ttfbSum / time.Duration(len(ttfbs))
	s.TTFBP50 = percentile(ttfbs, 50)
	s.TTFBP95 = percentile(ttfbs, 95)
	s.TTFBP99 = percentile(ttfbs, 99)

	// Container startup stats
	if len(startups) > 0 {
		sort.Slice(startups, func(i, j int) bool { return startups[i] < startups[j] })
		s.ContainerStartupMin = startups[0]
		s.ContainerStartupMax = startups[len(startups)-1]
		s.ContainerStartupAvg = startupSum / time.Duration(len(startups))
	}
}

// percentile calculates the p-th percentile of a sorted slice.
func percentile(sorted []time.Duration, p int) time.Duration {
	if len(sorted) == 0 {
		return 0
	}
	if p <= 0 {
		return sorted[0]
	}
	if p >= 100 {
		return sorted[len(sorted)-1]
	}

	// Calculate index using nearest rank method
	idx := (p * len(sorted)) / 100
	if idx >= len(sorted) {
		idx = len(sorted) - 1
	}

	return sorted[idx]
}

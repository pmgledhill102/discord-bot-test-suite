package benchmark

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"sort"
	"sync"
	"time"

	"github.com/pmgledhill102/discord-bot-test-suite/tests/cloudrun/internal/signing"
)

// WarmRequestConfig contains configuration for warm request benchmarking.
type WarmRequestConfig struct {
	ServiceURL   string
	RequestCount int
	Concurrency  int
	Signer       *signing.Signer
	RequestType  RequestType // Ping or SlashCommand
}

// RequestType specifies the type of Discord request to send.
type RequestType int

const (
	RequestTypePing RequestType = iota
	RequestTypeSlashCommand
)

// WarmRequestResult contains the result of a single warm request.
type WarmRequestResult struct {
	Latency    time.Duration
	StatusCode int
	Error      error
}

// WarmRequestStats contains aggregated statistics from warm request benchmarking.
type WarmRequestStats struct {
	// Request counts
	TotalRequests int
	Successful    int
	Failed        int

	// Latency statistics
	Min time.Duration
	Max time.Duration
	Avg time.Duration
	P50 time.Duration
	P95 time.Duration
	P99 time.Duration

	// Throughput
	Duration           time.Duration
	RequestsPerSecond  float64

	// Individual results (for detailed analysis)
	Results []WarmRequestResult
}

// RunWarmRequestBenchmark runs a warm request benchmark with concurrent workers.
func RunWarmRequestBenchmark(ctx context.Context, cfg WarmRequestConfig) (*WarmRequestStats, error) {
	if cfg.RequestCount == 0 {
		cfg.RequestCount = 100
	}
	if cfg.Concurrency == 0 {
		cfg.Concurrency = 10
	}

	// Create work channel and results channel
	work := make(chan int, cfg.RequestCount)
	results := make(chan WarmRequestResult, cfg.RequestCount)

	// Fill work channel
	for i := 0; i < cfg.RequestCount; i++ {
		work <- i
	}
	close(work)

	// Create HTTP client (reused across workers)
	client := &http.Client{
		Timeout: 30 * time.Second,
		Transport: &http.Transport{
			MaxIdleConns:        cfg.Concurrency * 2,
			MaxIdleConnsPerHost: cfg.Concurrency * 2,
			IdleConnTimeout:     90 * time.Second,
		},
	}

	// Get request body based on type
	var body []byte
	switch cfg.RequestType {
	case RequestTypeSlashCommand:
		body = signing.DiscordSlashCommandRequest()
	default:
		body = signing.DiscordPingRequest()
	}

	// Start workers
	var wg sync.WaitGroup
	startTime := time.Now()

	for i := 0; i < cfg.Concurrency; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			worker(ctx, client, cfg.ServiceURL, body, cfg.Signer, work, results)
		}()
	}

	// Wait for all workers to complete
	go func() {
		wg.Wait()
		close(results)
	}()

	// Collect results
	stats := &WarmRequestStats{
		Results: make([]WarmRequestResult, 0, cfg.RequestCount),
	}

	for result := range results {
		stats.Results = append(stats.Results, result)
		stats.TotalRequests++
		if result.Error == nil && result.StatusCode == http.StatusOK {
			stats.Successful++
		} else {
			stats.Failed++
		}
	}

	stats.Duration = time.Since(startTime)

	// Calculate statistics
	stats.calculateStats()

	return stats, nil
}

// worker processes requests from the work channel.
func worker(ctx context.Context, client *http.Client, serviceURL string, body []byte, signer *signing.Signer, work <-chan int, results chan<- WarmRequestResult) {
	for range work {
		select {
		case <-ctx.Done():
			results <- WarmRequestResult{Error: ctx.Err()}
			return
		default:
		}

		result := makeRequest(ctx, client, serviceURL, body, signer)
		results <- result
	}
}

// makeRequest performs a single HTTP request and measures latency.
func makeRequest(ctx context.Context, client *http.Client, serviceURL string, body []byte, signer *signing.Signer) WarmRequestResult {
	result := WarmRequestResult{}

	// Sign the request
	signature, timestamp := signer.SignRequest(body)

	// Create request
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, serviceURL, bytes.NewReader(body))
	if err != nil {
		result.Error = fmt.Errorf("creating request: %w", err)
		return result
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Signature-Ed25519", signature)
	req.Header.Set("X-Signature-Timestamp", timestamp)

	// Make request and measure latency
	start := time.Now()
	resp, err := client.Do(req)
	if err != nil {
		result.Error = fmt.Errorf("making request: %w", err)
		result.Latency = time.Since(start)
		return result
	}
	defer resp.Body.Close()

	// Read response body to complete the request
	_, _ = io.ReadAll(resp.Body)

	result.Latency = time.Since(start)
	result.StatusCode = resp.StatusCode

	if resp.StatusCode != http.StatusOK {
		result.Error = fmt.Errorf("unexpected status code: %d", resp.StatusCode)
	}

	return result
}

// calculateStats computes aggregate statistics from individual results.
func (s *WarmRequestStats) calculateStats() {
	if len(s.Results) == 0 {
		return
	}

	// Collect successful latencies
	var latencies []time.Duration
	var latencySum time.Duration

	for _, r := range s.Results {
		if r.Error == nil {
			latencies = append(latencies, r.Latency)
			latencySum += r.Latency
		}
	}

	if len(latencies) == 0 {
		return
	}

	// Sort for percentile calculations
	sort.Slice(latencies, func(i, j int) bool { return latencies[i] < latencies[j] })

	// Calculate stats
	s.Min = latencies[0]
	s.Max = latencies[len(latencies)-1]
	s.Avg = latencySum / time.Duration(len(latencies))
	s.P50 = percentile(latencies, 50)
	s.P95 = percentile(latencies, 95)
	s.P99 = percentile(latencies, 99)

	// Calculate throughput
	if s.Duration > 0 {
		s.RequestsPerSecond = float64(s.TotalRequests) / s.Duration.Seconds()
	}
}

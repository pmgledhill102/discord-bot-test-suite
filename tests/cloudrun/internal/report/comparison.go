package report

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/pmgledhill102/discord-bot-test-suite/tests/cloudrun/internal/benchmark"
)

// LocalBenchmarkResult represents the structure of local benchmark results.
// This matches the format from the local performance testing infrastructure.
type LocalBenchmarkResult struct {
	Services map[string]LocalServiceResult `json:"services"`
}

// LocalServiceResult contains local benchmark data for a service.
type LocalServiceResult struct {
	ImageSize         string  `json:"image_size"`
	ContainerStartup  string  `json:"container_startup"`
	TimeToFirstPing   string  `json:"time_to_first_ping"`
	MemoryUsage       string  `json:"memory_usage"`
	PingP50           string  `json:"ping_p50"`
	PingP95           string  `json:"ping_p95"`
	PingP99           string  `json:"ping_p99"`
}

// ComparisonReport contains the comparison between local and Cloud Run results.
type ComparisonReport struct {
	LocalResults    *LocalBenchmarkResult
	CloudRunResults *benchmark.BenchmarkResult
	Services        map[string]*ServiceComparison
}

// ServiceComparison contains comparison data for a single service.
type ServiceComparison struct {
	ServiceName string

	// Local results
	LocalStartup    time.Duration
	LocalFirstPing  time.Duration
	LocalP50        time.Duration

	// Cloud Run results
	CloudRunColdStart time.Duration
	CloudRunP50       time.Duration

	// Deltas
	ColdStartDelta    time.Duration
	ColdStartRatio    float64
	WarmLatencyDelta  time.Duration
	WarmLatencyRatio  float64
}

// LoadLocalResults loads local benchmark results from a JSON file.
func LoadLocalResults(path string) (*LocalBenchmarkResult, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading local results: %w", err)
	}

	var results LocalBenchmarkResult
	if err := json.Unmarshal(data, &results); err != nil {
		return nil, fmt.Errorf("parsing local results: %w", err)
	}

	return &results, nil
}

// Compare creates a comparison report between local and Cloud Run results.
func Compare(local *LocalBenchmarkResult, cloudrun *benchmark.BenchmarkResult) *ComparisonReport {
	report := &ComparisonReport{
		LocalResults:    local,
		CloudRunResults: cloudrun,
		Services:        make(map[string]*ServiceComparison),
	}

	// Compare each service that exists in both
	for name, crSvc := range cloudrun.Services {
		localSvc, ok := local.Services[name]
		if !ok {
			continue
		}

		comparison := &ServiceComparison{
			ServiceName: name,
		}

		// Parse local results
		if d, err := time.ParseDuration(localSvc.TimeToFirstPing); err == nil {
			comparison.LocalFirstPing = d
		}
		if d, err := time.ParseDuration(localSvc.ContainerStartup); err == nil {
			comparison.LocalStartup = d
		}
		if d, err := time.ParseDuration(localSvc.PingP50); err == nil {
			comparison.LocalP50 = d
		}

		// Get Cloud Run results
		if crSvc.ColdStart != nil {
			comparison.CloudRunColdStart = crSvc.ColdStart.TTFBP50
		}
		if crSvc.WarmRequest != nil {
			comparison.CloudRunP50 = crSvc.WarmRequest.P50
		}

		// Calculate deltas
		if comparison.LocalFirstPing > 0 && comparison.CloudRunColdStart > 0 {
			comparison.ColdStartDelta = comparison.CloudRunColdStart - comparison.LocalFirstPing
			comparison.ColdStartRatio = float64(comparison.CloudRunColdStart) / float64(comparison.LocalFirstPing)
		}

		if comparison.LocalP50 > 0 && comparison.CloudRunP50 > 0 {
			comparison.WarmLatencyDelta = comparison.CloudRunP50 - comparison.LocalP50
			comparison.WarmLatencyRatio = float64(comparison.CloudRunP50) / float64(comparison.LocalP50)
		}

		report.Services[name] = comparison
	}

	return report
}

// WriteComparisonMarkdown writes a comparison report to a Markdown file.
func WriteComparisonMarkdown(report *ComparisonReport, path string) error {
	var sb strings.Builder

	sb.WriteString("# Local vs Cloud Run Comparison\n\n")
	sb.WriteString(fmt.Sprintf("**Cloud Run Run ID:** `%s`\n\n", report.CloudRunResults.RunID))
	sb.WriteString(fmt.Sprintf("**Date:** %s\n\n", report.CloudRunResults.StartTime.Format("2006-01-02 15:04:05 UTC")))

	// Cold Start Comparison
	sb.WriteString("## Cold Start Comparison\n\n")
	sb.WriteString("| Service | Local First Ping | Cloud Run P50 | Delta | Ratio |\n")
	sb.WriteString("|---------|-----------------|---------------|-------|-------|\n")

	for name, cmp := range report.Services {
		localStr := formatDuration(cmp.LocalFirstPing)
		cloudStr := formatDuration(cmp.CloudRunColdStart)
		deltaStr := formatDelta(cmp.ColdStartDelta)
		ratioStr := "-"
		if cmp.ColdStartRatio > 0 {
			ratioStr = fmt.Sprintf("%.1fx", cmp.ColdStartRatio)
		}

		sb.WriteString(fmt.Sprintf("| %s | %s | %s | %s | %s |\n",
			name, localStr, cloudStr, deltaStr, ratioStr))
	}
	sb.WriteString("\n")

	// Warm Latency Comparison
	sb.WriteString("## Warm Latency Comparison\n\n")
	sb.WriteString("| Service | Local P50 | Cloud Run P50 | Delta | Ratio |\n")
	sb.WriteString("|---------|-----------|---------------|-------|-------|\n")

	for name, cmp := range report.Services {
		localStr := formatDuration(cmp.LocalP50)
		cloudStr := formatDuration(cmp.CloudRunP50)
		deltaStr := formatDelta(cmp.WarmLatencyDelta)
		ratioStr := "-"
		if cmp.WarmLatencyRatio > 0 {
			ratioStr = fmt.Sprintf("%.1fx", cmp.WarmLatencyRatio)
		}

		sb.WriteString(fmt.Sprintf("| %s | %s | %s | %s | %s |\n",
			name, localStr, cloudStr, deltaStr, ratioStr))
	}
	sb.WriteString("\n")

	// Analysis
	sb.WriteString("## Analysis\n\n")
	findings := analyzeComparison(report)
	for _, finding := range findings {
		sb.WriteString(fmt.Sprintf("- %s\n", finding))
	}
	sb.WriteString("\n")

	// Notes
	sb.WriteString("## Notes\n\n")
	sb.WriteString("- **Local**: Docker containers running on development machine\n")
	sb.WriteString("- **Cloud Run**: Deployed to GCP Cloud Run with gen2 execution environment\n")
	sb.WriteString("- **Delta**: Cloud Run - Local (positive = Cloud Run is slower)\n")
	sb.WriteString("- **Ratio**: Cloud Run / Local (>1 = Cloud Run is slower)\n")

	if err := os.WriteFile(path, []byte(sb.String()), 0644); err != nil {
		return fmt.Errorf("writing file: %w", err)
	}

	return nil
}

// formatDelta formats a duration delta for display.
func formatDelta(d time.Duration) string {
	if d == 0 {
		return "-"
	}
	if d > 0 {
		return fmt.Sprintf("+%s", formatDuration(d))
	}
	return fmt.Sprintf("-%s", formatDuration(-d))
}

// analyzeComparison generates findings from the comparison.
func analyzeComparison(report *ComparisonReport) []string {
	var findings []string

	// Calculate average cold start overhead
	var totalRatio float64
	var count int
	for _, cmp := range report.Services {
		if cmp.ColdStartRatio > 0 {
			totalRatio += cmp.ColdStartRatio
			count++
		}
	}

	if count > 0 {
		avgRatio := totalRatio / float64(count)
		findings = append(findings, fmt.Sprintf("Average cold start overhead: %.1fx compared to local Docker", avgRatio))
	}

	// Find services with highest and lowest overhead
	var highestOverhead, lowestOverhead string
	var highestRatio, lowestRatio float64

	for name, cmp := range report.Services {
		if cmp.ColdStartRatio <= 0 {
			continue
		}
		if highestRatio == 0 || cmp.ColdStartRatio > highestRatio {
			highestRatio = cmp.ColdStartRatio
			highestOverhead = name
		}
		if lowestRatio == 0 || cmp.ColdStartRatio < lowestRatio {
			lowestRatio = cmp.ColdStartRatio
			lowestOverhead = name
		}
	}

	if highestOverhead != "" {
		findings = append(findings, fmt.Sprintf("Highest cold start overhead: %s (%.1fx)", highestOverhead, highestRatio))
	}
	if lowestOverhead != "" {
		findings = append(findings, fmt.Sprintf("Lowest cold start overhead: %s (%.1fx)", lowestOverhead, lowestRatio))
	}

	// Warm latency analysis
	var warmTotalRatio float64
	var warmCount int
	for _, cmp := range report.Services {
		if cmp.WarmLatencyRatio > 0 {
			warmTotalRatio += cmp.WarmLatencyRatio
			warmCount++
		}
	}

	if warmCount > 0 {
		avgWarmRatio := warmTotalRatio / float64(warmCount)
		findings = append(findings, fmt.Sprintf("Average warm latency overhead: %.1fx compared to local Docker", avgWarmRatio))
	}

	return findings
}

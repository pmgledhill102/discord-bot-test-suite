package report

import (
	"fmt"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/pmgledhill102/discord-bot-test-suite/tests/cloudrun/internal/benchmark"
)

// WriteMarkdown writes benchmark results to a Markdown file.
func WriteMarkdown(result *benchmark.BenchmarkResult, path string) error {
	var sb strings.Builder

	// Header
	sb.WriteString("# Cloud Run Cold Start Benchmark Results\n\n")
	sb.WriteString(fmt.Sprintf("**Run ID:** `%s`\n\n", result.RunID))
	sb.WriteString(fmt.Sprintf("**Date:** %s\n\n", result.StartTime.Format("2006-01-02 15:04:05 UTC")))
	sb.WriteString(fmt.Sprintf("**Duration:** %s\n\n", result.EndTime.Sub(result.StartTime).Round(time.Second)))
	sb.WriteString(fmt.Sprintf("**Project:** %s\n\n", result.Config.GCP.ProjectID))
	sb.WriteString(fmt.Sprintf("**Region:** %s\n\n", result.Config.GCP.Region))

	// Configuration
	sb.WriteString("## Configuration\n\n")
	profile := result.Config.GetProfile("default")
	sb.WriteString("| Setting | Value |\n")
	sb.WriteString("|---------|-------|\n")
	sb.WriteString(fmt.Sprintf("| CPU | %s |\n", profile.CPU))
	sb.WriteString(fmt.Sprintf("| Memory | %s |\n", profile.Memory))
	sb.WriteString(fmt.Sprintf("| Execution Environment | %s |\n", profile.ExecutionEnv))
	sb.WriteString(fmt.Sprintf("| Startup CPU Boost | %t |\n", profile.StartupCPUBoost))
	sb.WriteString(fmt.Sprintf("| Cold Start Iterations | %d |\n", result.Config.Benchmark.ColdStartIterations))
	sb.WriteString(fmt.Sprintf("| Scale-to-Zero Timeout | %s |\n", result.Config.Benchmark.ScaleToZeroTimeout))
	sb.WriteString(fmt.Sprintf("| Warm Requests | %d |\n", result.Config.Benchmark.WarmRequests))
	sb.WriteString(fmt.Sprintf("| Warm Concurrency | %d |\n", result.Config.Benchmark.WarmConcurrency))
	sb.WriteString(fmt.Sprintf("| Services Tested | %d |\n", len(result.Config.Services.Enabled)))
	sb.WriteString("\n")

	// Add warning for quick tests
	if result.Config.Benchmark.ScaleToZeroTimeout < 5*time.Minute {
		sb.WriteString("> **Note:** This is a quick validation test with a short scale-to-zero timeout. ")
		sb.WriteString("Results may not reflect true cold start performance. ")
		sb.WriteString("For accurate measurements, use the scheduled full benchmark with 15-20 minute timeout.\n\n")
	}

	// Cold Start Results
	sb.WriteString("## Cold Start Results\n\n")
	sb.WriteString("| Service | P50 | P95 | P99 | Min | Max | Success |\n")
	sb.WriteString("|---------|-----|-----|-----|-----|-----|--------|\n")

	// Sort services by P50 cold start time
	type serviceStats struct {
		name string
		svc  *benchmark.ServiceResult
	}
	var sortedServices []serviceStats
	for name, svc := range result.Services {
		sortedServices = append(sortedServices, serviceStats{name, svc})
	}
	sort.Slice(sortedServices, func(i, j int) bool {
		iP50 := time.Duration(0)
		jP50 := time.Duration(0)
		if sortedServices[i].svc.ColdStart != nil {
			iP50 = sortedServices[i].svc.ColdStart.TTFBP50
		}
		if sortedServices[j].svc.ColdStart != nil {
			jP50 = sortedServices[j].svc.ColdStart.TTFBP50
		}
		return iP50 < jP50
	})

	for _, ss := range sortedServices {
		if ss.svc.ColdStart != nil {
			cs := ss.svc.ColdStart
			sb.WriteString(fmt.Sprintf("| %s | %s | %s | %s | %s | %s | %d/%d |\n",
				ss.name,
				formatDuration(cs.TTFBP50),
				formatDuration(cs.TTFBP95),
				formatDuration(cs.TTFBP99),
				formatDuration(cs.TTFBMin),
				formatDuration(cs.TTFBMax),
				cs.SuccessCount,
				cs.SuccessCount+cs.FailureCount,
			))
		} else if ss.svc.DeployError != nil {
			sb.WriteString(fmt.Sprintf("| %s | - | - | - | - | - | Deploy failed |\n", ss.name))
		} else {
			sb.WriteString(fmt.Sprintf("| %s | - | - | - | - | - | No data |\n", ss.name))
		}
	}
	sb.WriteString("\n")

	// Warm Request Results
	sb.WriteString("## Warm Request Results\n\n")
	sb.WriteString("| Service | P50 | P95 | P99 | Req/s | Success Rate |\n")
	sb.WriteString("|---------|-----|-----|-----|-------|-------------|\n")

	// Sort by P50 warm latency
	sort.Slice(sortedServices, func(i, j int) bool {
		iP50 := time.Duration(0)
		jP50 := time.Duration(0)
		if sortedServices[i].svc.WarmRequest != nil {
			iP50 = sortedServices[i].svc.WarmRequest.P50
		}
		if sortedServices[j].svc.WarmRequest != nil {
			jP50 = sortedServices[j].svc.WarmRequest.P50
		}
		return iP50 < jP50
	})

	for _, ss := range sortedServices {
		if ss.svc.WarmRequest != nil {
			wr := ss.svc.WarmRequest
			successRate := float64(wr.Successful) / float64(wr.TotalRequests) * 100
			sb.WriteString(fmt.Sprintf("| %s | %s | %s | %s | %.1f | %.1f%% |\n",
				ss.name,
				formatDuration(wr.P50),
				formatDuration(wr.P95),
				formatDuration(wr.P99),
				wr.RequestsPerSecond,
				successRate,
			))
		} else {
			sb.WriteString(fmt.Sprintf("| %s | - | - | - | - | - |\n", ss.name))
		}
	}
	sb.WriteString("\n")

	// Key Findings
	sb.WriteString("## Key Findings\n\n")
	findings := generateFindings(result)
	for _, finding := range findings {
		sb.WriteString(fmt.Sprintf("- %s\n", finding))
	}
	sb.WriteString("\n")

	// Errors (if any)
	var errors []string
	for name, svc := range result.Services {
		if svc.DeployError != nil {
			errors = append(errors, fmt.Sprintf("**%s**: Deploy error - %v", name, svc.DeployError))
		} else if svc.BenchmarkError != nil {
			errors = append(errors, fmt.Sprintf("**%s**: Benchmark error - %v", name, svc.BenchmarkError))
		}
	}

	if len(errors) > 0 {
		sb.WriteString("## Errors\n\n")
		for _, err := range errors {
			sb.WriteString(fmt.Sprintf("- %s\n", err))
		}
		sb.WriteString("\n")
	}

	// Write to file
	if err := os.WriteFile(path, []byte(sb.String()), 0644); err != nil {
		return fmt.Errorf("writing file: %w", err)
	}

	return nil
}

// formatDuration formats a duration for display in tables.
func formatDuration(d time.Duration) string {
	if d == 0 {
		return "-"
	}
	if d < time.Millisecond {
		return fmt.Sprintf("%.2fµs", float64(d.Microseconds()))
	}
	if d < time.Second {
		return fmt.Sprintf("%.1fms", float64(d.Milliseconds()))
	}
	return fmt.Sprintf("%.2fs", d.Seconds())
}

// generateFindings analyzes results and generates key findings.
func generateFindings(result *benchmark.BenchmarkResult) []string {
	var findings []string

	// Find fastest and slowest cold start
	var fastestColdStart, slowestColdStart string
	var fastestColdStartTime, slowestColdStartTime time.Duration

	for name, svc := range result.Services {
		if svc.ColdStart == nil {
			continue
		}
		p50 := svc.ColdStart.TTFBP50
		if fastestColdStartTime == 0 || p50 < fastestColdStartTime {
			fastestColdStartTime = p50
			fastestColdStart = name
		}
		if p50 > slowestColdStartTime {
			slowestColdStartTime = p50
			slowestColdStart = name
		}
	}

	if fastestColdStart != "" {
		findings = append(findings, fmt.Sprintf("**Fastest cold start:** %s with P50 of %s",
			fastestColdStart, formatDuration(fastestColdStartTime)))
	}

	if slowestColdStart != "" && slowestColdStart != fastestColdStart {
		findings = append(findings, fmt.Sprintf("**Slowest cold start:** %s with P50 of %s",
			slowestColdStart, formatDuration(slowestColdStartTime)))
	}

	if fastestColdStartTime > 0 && slowestColdStartTime > 0 {
		ratio := float64(slowestColdStartTime) / float64(fastestColdStartTime)
		findings = append(findings, fmt.Sprintf("Cold start variance: %.1fx difference between fastest and slowest", ratio))
	}

	// Find highest throughput
	var highestThroughput float64
	var highestThroughputService string
	for name, svc := range result.Services {
		if svc.WarmRequest == nil {
			continue
		}
		if svc.WarmRequest.RequestsPerSecond > highestThroughput {
			highestThroughput = svc.WarmRequest.RequestsPerSecond
			highestThroughputService = name
		}
	}

	if highestThroughputService != "" {
		findings = append(findings, fmt.Sprintf("**Highest throughput:** %s at %.1f req/s",
			highestThroughputService, highestThroughput))
	}

	// Count services by cold start category
	var sub500ms, sub1s, sub2s, over2s int
	for _, svc := range result.Services {
		if svc.ColdStart == nil {
			continue
		}
		p50 := svc.ColdStart.TTFBP50
		switch {
		case p50 < 500*time.Millisecond:
			sub500ms++
		case p50 < time.Second:
			sub1s++
		case p50 < 2*time.Second:
			sub2s++
		default:
			over2s++
		}
	}

	if sub500ms > 0 {
		findings = append(findings, fmt.Sprintf("%d services with cold start under 500ms", sub500ms))
	}
	if over2s > 0 {
		findings = append(findings, fmt.Sprintf("%d services with cold start over 2s", over2s))
	}

	return findings
}

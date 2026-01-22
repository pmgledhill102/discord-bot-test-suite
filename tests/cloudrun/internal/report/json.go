// Package report provides benchmark result formatting and output.
package report

import (
	"encoding/json"
	"fmt"
	"os"
	"time"

	"github.com/pmgledhill102/discord-bot-test-suite/tests/cloudrun/internal/benchmark"
)

// JSONReport represents the JSON output format for benchmark results.
type JSONReport struct {
	RunID     string                        `json:"run_id"`
	StartTime time.Time                     `json:"start_time"`
	EndTime   time.Time                     `json:"end_time"`
	Duration  string                        `json:"duration"`
	Config    JSONConfigSummary             `json:"config"`
	Services  map[string]JSONServiceReport  `json:"services"`
	Summary   JSONSummary                   `json:"summary"`
}

// JSONConfigSummary contains configuration information for the report.
type JSONConfigSummary struct {
	ProjectID string `json:"project_id"`
	Region    string `json:"region"`
	Profile   string `json:"profile"`

	// Benchmark settings - important for distinguishing quick tests from full benchmarks
	ColdStartIterations  int    `json:"cold_start_iterations"`
	ScaleToZeroTimeout   string `json:"scale_to_zero_timeout"`
	WarmRequests         int    `json:"warm_requests"`
	WarmConcurrency      int    `json:"warm_concurrency"`
	ServicesEnabled      []string `json:"services_enabled"`

	// Profile settings
	CPU             string `json:"cpu"`
	Memory          string `json:"memory"`
	ExecutionEnv    string `json:"execution_env"`
	StartupCPUBoost bool   `json:"startup_cpu_boost"`
}

// JSONServiceReport contains benchmark results for a single service.
type JSONServiceReport struct {
	ServiceName        string              `json:"service_name"`
	ServiceURL         string              `json:"service_url"`
	Image              string              `json:"image"`
	DeploymentDuration string              `json:"deployment_duration"`
	ColdStart          *JSONColdStartStats `json:"cold_start,omitempty"`
	WarmRequest        *JSONWarmStats      `json:"warm_request,omitempty"`
	Error              string              `json:"error,omitempty"`
}

// JSONColdStartStats contains cold start statistics in JSON format.
type JSONColdStartStats struct {
	Iterations   int    `json:"iterations"`
	SuccessCount int    `json:"success_count"`
	FailureCount int    `json:"failure_count"`
	TTFBMin      string `json:"ttfb_min"`
	TTFBMax      string `json:"ttfb_max"`
	TTFBAvg      string `json:"ttfb_avg"`
	TTFBP50      string `json:"ttfb_p50"`
	TTFBP95      string `json:"ttfb_p95"`
	TTFBP99      string `json:"ttfb_p99"`
}

// JSONWarmStats contains warm request statistics in JSON format.
type JSONWarmStats struct {
	TotalRequests     int     `json:"total_requests"`
	Successful        int     `json:"successful"`
	Failed            int     `json:"failed"`
	Duration          string  `json:"duration"`
	RequestsPerSecond float64 `json:"requests_per_second"`
	Min               string  `json:"min"`
	Max               string  `json:"max"`
	Avg               string  `json:"avg"`
	P50               string  `json:"p50"`
	P95               string  `json:"p95"`
	P99               string  `json:"p99"`
}

// JSONSummary contains overall benchmark summary.
type JSONSummary struct {
	TotalServices   int    `json:"total_services"`
	SuccessfulTests int    `json:"successful_tests"`
	FailedTests     int    `json:"failed_tests"`
	FastestColdStart string `json:"fastest_cold_start"`
	FastestService   string `json:"fastest_service"`
}

// WriteJSON writes benchmark results to a JSON file.
func WriteJSON(result *benchmark.BenchmarkResult, path string) error {
	report := toJSONReport(result)

	data, err := json.MarshalIndent(report, "", "  ")
	if err != nil {
		return fmt.Errorf("marshaling JSON: %w", err)
	}

	if err := os.WriteFile(path, data, 0644); err != nil {
		return fmt.Errorf("writing file: %w", err)
	}

	return nil
}

// toJSONReport converts benchmark results to JSON report format.
func toJSONReport(result *benchmark.BenchmarkResult) *JSONReport {
	profile := result.Config.GetProfile("default")

	report := &JSONReport{
		RunID:     result.RunID,
		StartTime: result.StartTime,
		EndTime:   result.EndTime,
		Duration:  result.EndTime.Sub(result.StartTime).String(),
		Config: JSONConfigSummary{
			ProjectID: result.Config.GCP.ProjectID,
			Region:    result.Config.GCP.Region,
			Profile:   "default",

			// Benchmark settings
			ColdStartIterations:  result.Config.Benchmark.ColdStartIterations,
			ScaleToZeroTimeout:   result.Config.Benchmark.ScaleToZeroTimeout.String(),
			WarmRequests:         result.Config.Benchmark.WarmRequests,
			WarmConcurrency:      result.Config.Benchmark.WarmConcurrency,
			ServicesEnabled:      result.Config.Services.Enabled,

			// Profile settings
			CPU:             profile.CPU,
			Memory:          profile.Memory,
			ExecutionEnv:    profile.ExecutionEnv,
			StartupCPUBoost: profile.StartupCPUBoost,
		},
		Services: make(map[string]JSONServiceReport),
	}

	var fastestColdStart time.Duration
	var fastestService string
	var successfulTests, failedTests int

	for name, svc := range result.Services {
		serviceReport := JSONServiceReport{
			ServiceName:        svc.ServiceName,
			ServiceURL:         svc.ServiceURL,
			Image:              svc.Image,
			DeploymentDuration: svc.DeploymentDuration.String(),
		}

		if svc.DeployError != nil {
			serviceReport.Error = svc.DeployError.Error()
			failedTests++
		} else if svc.BenchmarkError != nil {
			serviceReport.Error = svc.BenchmarkError.Error()
			failedTests++
		} else {
			successfulTests++
		}

		if svc.ColdStart != nil {
			serviceReport.ColdStart = &JSONColdStartStats{
				Iterations:   len(svc.ColdStart.Results),
				SuccessCount: svc.ColdStart.SuccessCount,
				FailureCount: svc.ColdStart.FailureCount,
				TTFBMin:      svc.ColdStart.TTFBMin.String(),
				TTFBMax:      svc.ColdStart.TTFBMax.String(),
				TTFBAvg:      svc.ColdStart.TTFBAvg.String(),
				TTFBP50:      svc.ColdStart.TTFBP50.String(),
				TTFBP95:      svc.ColdStart.TTFBP95.String(),
				TTFBP99:      svc.ColdStart.TTFBP99.String(),
			}

			// Track fastest service
			if fastestColdStart == 0 || svc.ColdStart.TTFBP50 < fastestColdStart {
				fastestColdStart = svc.ColdStart.TTFBP50
				fastestService = name
			}
		}

		if svc.WarmRequest != nil {
			serviceReport.WarmRequest = &JSONWarmStats{
				TotalRequests:     svc.WarmRequest.TotalRequests,
				Successful:        svc.WarmRequest.Successful,
				Failed:            svc.WarmRequest.Failed,
				Duration:          svc.WarmRequest.Duration.String(),
				RequestsPerSecond: svc.WarmRequest.RequestsPerSecond,
				Min:               svc.WarmRequest.Min.String(),
				Max:               svc.WarmRequest.Max.String(),
				Avg:               svc.WarmRequest.Avg.String(),
				P50:               svc.WarmRequest.P50.String(),
				P95:               svc.WarmRequest.P95.String(),
				P99:               svc.WarmRequest.P99.String(),
			}
		}

		report.Services[name] = serviceReport
	}

	report.Summary = JSONSummary{
		TotalServices:    len(result.Services),
		SuccessfulTests:  successfulTests,
		FailedTests:      failedTests,
		FastestColdStart: fastestColdStart.String(),
		FastestService:   fastestService,
	}

	return report
}

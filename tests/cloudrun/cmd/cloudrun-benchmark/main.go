// cloudrun-benchmark is a CLI tool for benchmarking Cloud Run cold start performance.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"path"
	"path/filepath"
	"time"

	"github.com/pmgledhill102/discord-bot-test-suite/tests/cloudrun/internal/benchmark"
	"github.com/pmgledhill102/discord-bot-test-suite/tests/cloudrun/internal/config"
	"github.com/pmgledhill102/discord-bot-test-suite/tests/cloudrun/internal/gcp"
	"github.com/pmgledhill102/discord-bot-test-suite/tests/cloudrun/internal/report"
	"github.com/pmgledhill102/discord-bot-test-suite/tests/cloudrun/internal/signing"
)

var (
	configPath   = flag.String("config", "/configs/scheduled-full.yaml", "Path to configuration file")
	outputDir    = flag.String("output", "results", "Output directory for results")
	services     = flag.String("services", "", "Comma-separated list of services to benchmark (overrides config)")
	localResults = flag.String("local-results", "", "Path to local benchmark results for comparison")
	batchMode    = flag.Bool("batch", false, "Run in batch mode (deploy all → wait → test all, more efficient)")
	gcsBucket    = flag.String("gcs-bucket", "", "GCS bucket for uploading results (env: GCS_RESULTS_BUCKET)")
	iteration    = flag.Int("iteration", 1, "Iteration number for measure command")
	noJitter     = flag.Bool("no-jitter", false, "Skip startup jitter (for testing)")
)

// startupJitter is the delay before executing scheduled jobs to avoid exact-minute contention.
const startupJitter = 37*time.Second + 300*time.Millisecond

func main() {
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: %s <command> [options]\n\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "Commands:\n")
		fmt.Fprintf(os.Stderr, "  adhoc     Run a complete single-iteration benchmark (DEFAULT)\n")
		fmt.Fprintf(os.Stderr, "            Waits for scale-to-zero, measures cold starts, runs warm tests\n")
		fmt.Fprintf(os.Stderr, "  measure   Take a cold start reading (for scheduled jobs)\n")
		fmt.Fprintf(os.Stderr, "            Saves reading to GCS: runs/<date>/reading-N.json\n")
		fmt.Fprintf(os.Stderr, "  finalize  Consolidate readings and generate reports (for scheduled jobs)\n")
		fmt.Fprintf(os.Stderr, "            Loads readings, runs warm tests, uploads final reports\n")
		fmt.Fprintf(os.Stderr, "  deploy    Deploy services without running benchmarks\n")
		fmt.Fprintf(os.Stderr, "  run       Run the full benchmark suite (legacy)\n")
		fmt.Fprintf(os.Stderr, "            Use --batch for efficient multi-service testing\n")
		fmt.Fprintf(os.Stderr, "  cleanup   Clean up resources for a specific run\n")
		fmt.Fprintf(os.Stderr, "  report    Generate reports from existing results\n")
		fmt.Fprintf(os.Stderr, "\nOptions:\n")
		flag.PrintDefaults()
	}

	// Default to adhoc if no command provided
	command := "adhoc"
	if len(os.Args) >= 2 && !isFlag(os.Args[1]) {
		command = os.Args[1]
		os.Args = append(os.Args[:1], os.Args[2:]...)
	}

	flag.Parse()

	ctx := context.Background()

	switch command {
	case "adhoc":
		if err := cmdAdhoc(ctx); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	case "measure":
		if err := cmdMeasure(ctx); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	case "finalize":
		if err := cmdFinalize(ctx); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	case "deploy":
		if err := cmdDeploy(ctx); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	case "run":
		if err := cmdRun(ctx); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	case "cleanup":
		if err := cmdCleanup(ctx); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	case "report":
		if err := cmdReport(ctx); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n", command)
		flag.Usage()
		os.Exit(1)
	}
}

// isFlag returns true if the argument looks like a flag.
func isFlag(arg string) bool {
	return len(arg) > 0 && arg[0] == '-'
}

// applyJitter sleeps for the startup jitter period unless --no-jitter is set.
func applyJitter() {
	if !*noJitter {
		fmt.Printf("Applying startup jitter: %v\n", startupJitter)
		time.Sleep(startupJitter)
	}
}

// getRunDate returns today's date in UTC as the run ID.
func getRunDate() string {
	return time.Now().UTC().Format("2006-01-02")
}

// getGCSBucket returns the GCS bucket from flag or environment.
func getGCSBucket() string {
	bucket := *gcsBucket
	if bucket == "" {
		bucket = os.Getenv("GCS_RESULTS_BUCKET")
	}
	return bucket
}

func loadConfig() (*config.Config, error) {
	cfg, err := config.Load(*configPath)
	if err != nil {
		return nil, fmt.Errorf("loading config: %w", err)
	}

	// Override services if specified on command line
	if *services != "" {
		cfg.Services.Enabled = splitServices(*services)
	}

	return cfg, nil
}

func splitServices(s string) []string {
	var result []string
	for _, svc := range filepath.SplitList(s) {
		if svc != "" {
			result = append(result, svc)
		}
	}
	// Also handle comma-separated
	if len(result) == 1 {
		result = nil
		for i := 0; i < len(s); i++ {
			j := i
			for j < len(s) && s[j] != ',' {
				j++
			}
			if j > i {
				result = append(result, s[i:j])
			}
			i = j
		}
	}
	return result
}

// cmdAdhoc runs a complete single-iteration benchmark.
// This is the DEFAULT command when clicking "Execute" in Cloud Console.
func cmdAdhoc(ctx context.Context) error {
	applyJitter()

	cfg, err := loadConfig()
	if err != nil {
		return err
	}

	bucket := getGCSBucket()
	if bucket == "" {
		return fmt.Errorf("GCS bucket required: set --gcs-bucket or GCS_RESULTS_BUCKET")
	}

	fmt.Println("=== Ad-hoc Benchmark Run ===")
	fmt.Printf("Config: %s\n", *configPath)
	fmt.Printf("Services: %v\n", cfg.Services.Enabled)
	fmt.Printf("GCS Bucket: %s\n", bucket)

	// Create Cloud Run client
	cloudrun, err := gcp.NewCloudRunClient(ctx, cfg.GCP.ProjectID, cfg.GCP.Region)
	if err != nil {
		return fmt.Errorf("creating Cloud Run client: %w", err)
	}

	// Get service URLs (services are already deployed via CI)
	fmt.Println("\nLooking up service URLs...")
	serviceInfos, err := cloudrun.GetAllServicesInfo(ctx, cfg.Services.Enabled)
	if err != nil {
		return fmt.Errorf("getting service URLs: %w", err)
	}

	if len(serviceInfos) == 0 {
		return fmt.Errorf("no services found - ensure services are deployed")
	}

	fmt.Printf("Found %d services:\n", len(serviceInfos))
	for _, svc := range serviceInfos {
		fmt.Printf("  %s -> %s\n", svc.ServiceKey, svc.URL)
	}

	// Pre-fetch ID tokens (exclude from cold start measurement)
	fmt.Println("\nPre-fetching ID tokens...")
	tokens := make(map[string]string)
	for _, svc := range serviceInfos {
		token, err := gcp.GetIDToken(ctx, svc.URL)
		if err != nil {
			return fmt.Errorf("getting ID token for %s: %w", svc.ServiceKey, err)
		}
		tokens[svc.ServiceKey] = token
	}
	fmt.Printf("Pre-fetched tokens for %d services\n", len(tokens))

	// Wait for scale-to-zero
	fmt.Println("\nWaiting for all services to scale to zero...")
	if err := waitForAllScaleToZero(ctx, cfg, serviceInfos); err != nil {
		return fmt.Errorf("waiting for scale-to-zero: %w", err)
	}
	fmt.Println("All services scaled to zero")

	// Take cold start measurements
	fmt.Println("\nTaking cold start measurements...")
	signer := signing.NewSigner()
	loggingClient, _ := gcp.NewLoggingClient(ctx, cfg.GCP.ProjectID)
	if loggingClient != nil {
		defer loggingClient.Close()
	}

	coldResults := takeColdStartMeasurements(ctx, cfg, serviceInfos, signer, loggingClient, tokens)

	// Run warm request tests (services are now warm)
	fmt.Println("\nRunning warm request tests...")
	warmResults := runWarmTests(ctx, cfg, serviceInfos, signer, tokens)

	// Build full benchmark result
	result := buildBenchmarkResult(cfg, serviceInfos, coldResults, warmResults)

	// Create output directory
	timestamp := time.Now().UTC()
	tsStr := timestamp.Format("2006-01-02T15-04-05Z")
	runDir := filepath.Join(*outputDir, "adhoc-"+tsStr)
	if err := os.MkdirAll(runDir, 0755); err != nil {
		return fmt.Errorf("creating output directory: %w", err)
	}

	// Write reports
	jsonPath := filepath.Join(runDir, "results.json")
	if err := report.WriteJSON(result, jsonPath); err != nil {
		return fmt.Errorf("writing JSON report: %w", err)
	}
	fmt.Printf("JSON report written to: %s\n", jsonPath)

	mdPath := filepath.Join(runDir, "results.md")
	if err := report.WriteMarkdown(result, mdPath); err != nil {
		return fmt.Errorf("writing Markdown report: %w", err)
	}
	fmt.Printf("Markdown report written to: %s\n", mdPath)

	// Upload to GCS adhoc directory
	fmt.Printf("\nUploading results to GCS: gs://%s/adhoc/%s/\n", bucket, tsStr)
	uploader, err := report.NewGCSUploader(ctx, bucket)
	if err != nil {
		return fmt.Errorf("creating GCS uploader: %w", err)
	}
	defer uploader.Close()

	paths, err := uploader.UploadAdhocResults(ctx, timestamp, runDir)
	if err != nil {
		return fmt.Errorf("uploading to GCS: %w", err)
	}
	for _, p := range paths {
		fmt.Printf("Uploaded: %s\n", p)
	}

	fmt.Println("\n=== Ad-hoc Benchmark Complete ===")
	return nil
}

// cmdMeasure takes a single cold start reading and saves it to GCS.
// Used by scheduled measure-N jobs.
func cmdMeasure(ctx context.Context) error {
	applyJitter()

	cfg, err := loadConfig()
	if err != nil {
		return err
	}

	bucket := getGCSBucket()
	if bucket == "" {
		return fmt.Errorf("GCS bucket required: set --gcs-bucket or GCS_RESULTS_BUCKET")
	}

	runDate := getRunDate()
	iterNum := *iteration

	fmt.Println("=== Measure Command ===")
	fmt.Printf("Run date: %s\n", runDate)
	fmt.Printf("Iteration: %d\n", iterNum)
	fmt.Printf("Config: %s\n", *configPath)
	fmt.Printf("Services: %v\n", cfg.Services.Enabled)

	// Create Cloud Run client
	cloudrun, err := gcp.NewCloudRunClient(ctx, cfg.GCP.ProjectID, cfg.GCP.Region)
	if err != nil {
		return fmt.Errorf("creating Cloud Run client: %w", err)
	}

	// Get service URLs
	fmt.Println("\nLooking up service URLs...")
	serviceInfos, err := cloudrun.GetAllServicesInfo(ctx, cfg.Services.Enabled)
	if err != nil {
		return fmt.Errorf("getting service URLs: %w", err)
	}

	if len(serviceInfos) == 0 {
		return fmt.Errorf("no services found - ensure services are deployed")
	}

	fmt.Printf("Found %d services\n", len(serviceInfos))

	// Pre-fetch ID tokens (exclude from cold start measurement)
	fmt.Println("\nPre-fetching ID tokens...")
	tokens := make(map[string]string)
	for _, svc := range serviceInfos {
		token, err := gcp.GetIDToken(ctx, svc.URL)
		if err != nil {
			return fmt.Errorf("getting ID token for %s: %w", svc.ServiceKey, err)
		}
		tokens[svc.ServiceKey] = token
	}
	fmt.Printf("Pre-fetched tokens for %d services\n", len(tokens))

	// Verify services are scaled to zero
	fmt.Println("\nVerifying services are scaled to zero...")
	if err := verifyScaledToZero(ctx, cfg, serviceInfos); err != nil {
		fmt.Printf("Warning: some services may not be at zero instances: %v\n", err)
		// Continue anyway - we still want to take measurements
	}

	// Take cold start measurements
	fmt.Println("\nTaking cold start measurements...")
	signer := signing.NewSigner()
	loggingClient, _ := gcp.NewLoggingClient(ctx, cfg.GCP.ProjectID)
	if loggingClient != nil {
		defer loggingClient.Close()
	}

	measurements := make(map[string]*report.ColdStartMeasurement)
	for _, svc := range serviceInfos {
		fmt.Printf("  Measuring %s...\n", svc.ServiceKey)

		requestStartTime := time.Now()
		result, err := benchmark.MeasureColdStart(ctx, svc.URL, signer, tokens[svc.ServiceKey])

		measurement := &report.ColdStartMeasurement{
			ServiceName: svc.ServiceName,
			ServiceURL:  svc.URL,
			StatusCode:  result.StatusCode,
		}

		if err != nil {
			measurement.Error = err.Error()
			fmt.Printf("    Error: %v\n", err)
		} else {
			measurement.TTFB = result.TTFB
			fmt.Printf("    TTFB: %v\n", result.TTFB)
		}

		// Try to get container startup time
		if loggingClient != nil && result.Error == nil {
			metrics, err := loggingClient.WaitForStartupLog(ctx, svc.ServiceName, cfg.GCP.Region, requestStartTime, 30*time.Second)
			if err == nil && metrics.Found {
				measurement.ContainerStartup = metrics.ContainerStartupLatency
				fmt.Printf("    Container startup: %v\n", measurement.ContainerStartup)
			}
		}

		measurements[svc.ServiceKey] = measurement
	}

	// Save reading to GCS
	readingResult := &report.ReadingResult{
		RunID:     runDate,
		Iteration: iterNum,
		Timestamp: time.Now(),
		Config:    cfg,
		Services:  measurements,
	}

	fmt.Printf("\nSaving reading to GCS...\n")
	uploader, err := report.NewGCSUploader(ctx, bucket)
	if err != nil {
		return fmt.Errorf("creating GCS uploader: %w", err)
	}
	defer uploader.Close()

	gcsPath, err := uploader.SaveReadingResult(ctx, runDate, iterNum, readingResult)
	if err != nil {
		return fmt.Errorf("saving reading: %w", err)
	}
	fmt.Printf("Saved: %s\n", gcsPath)

	fmt.Println("\n=== Measure Complete ===")
	return nil
}

// cmdFinalize consolidates readings and generates final reports.
// Used by the scheduled finalize job.
func cmdFinalize(ctx context.Context) error {
	applyJitter()

	cfg, err := loadConfig()
	if err != nil {
		return err
	}

	bucket := getGCSBucket()
	if bucket == "" {
		return fmt.Errorf("GCS bucket required: set --gcs-bucket or GCS_RESULTS_BUCKET")
	}

	runDate := getRunDate()

	fmt.Println("=== Finalize Command ===")
	fmt.Printf("Run date: %s\n", runDate)
	fmt.Printf("Config: %s\n", *configPath)
	fmt.Printf("GCS Bucket: %s\n", bucket)

	// Create GCS uploader
	uploader, err := report.NewGCSUploader(ctx, bucket)
	if err != nil {
		return fmt.Errorf("creating GCS uploader: %w", err)
	}
	defer uploader.Close()

	// Load all readings from GCS
	fmt.Println("\nLoading readings from GCS...")
	readings, err := uploader.LoadAllReadings(ctx, runDate)
	if err != nil {
		return fmt.Errorf("loading readings: %w", err)
	}

	if len(readings) == 0 {
		return fmt.Errorf("no readings found for %s", runDate)
	}

	fmt.Printf("Loaded %d readings\n", len(readings))
	for _, r := range readings {
		fmt.Printf("  Iteration %d: %d services measured\n", r.Iteration, len(r.Services))
	}

	// Create Cloud Run client for warm tests
	cloudrun, err := gcp.NewCloudRunClient(ctx, cfg.GCP.ProjectID, cfg.GCP.Region)
	if err != nil {
		return fmt.Errorf("creating Cloud Run client: %w", err)
	}

	// Get service URLs for warm tests
	serviceInfos, err := cloudrun.GetAllServicesInfo(ctx, cfg.Services.Enabled)
	if err != nil {
		return fmt.Errorf("getting service URLs: %w", err)
	}

	// Pre-fetch ID tokens for warm tests
	fmt.Println("\nPre-fetching ID tokens...")
	tokens := make(map[string]string)
	for _, svc := range serviceInfos {
		token, err := gcp.GetIDToken(ctx, svc.URL)
		if err != nil {
			return fmt.Errorf("getting ID token for %s: %w", svc.ServiceKey, err)
		}
		tokens[svc.ServiceKey] = token
	}
	fmt.Printf("Pre-fetched tokens for %d services\n", len(tokens))

	// Run warm request tests (services are warm from recent cold start tests)
	fmt.Println("\nRunning warm request tests...")
	signer := signing.NewSigner()
	warmResults := runWarmTests(ctx, cfg, serviceInfos, signer, tokens)

	// Consolidate into benchmark result
	result := consolidateReadings(cfg, readings, serviceInfos, warmResults)

	// Create output directory
	runDir := filepath.Join(*outputDir, runDate)
	if err := os.MkdirAll(runDir, 0755); err != nil {
		return fmt.Errorf("creating output directory: %w", err)
	}

	// Write reports
	jsonPath := filepath.Join(runDir, "results.json")
	if err := report.WriteJSON(result, jsonPath); err != nil {
		return fmt.Errorf("writing JSON report: %w", err)
	}
	fmt.Printf("JSON report written to: %s\n", jsonPath)

	mdPath := filepath.Join(runDir, "results.md")
	if err := report.WriteMarkdown(result, mdPath); err != nil {
		return fmt.Errorf("writing Markdown report: %w", err)
	}
	fmt.Printf("Markdown report written to: %s\n", mdPath)

	// Upload final reports to GCS: YYYY/MM/DD/<run-id>/
	datePath := result.StartTime.UTC().Format("2006/01/02")
	gcsPrefix := path.Join(datePath, result.RunID)

	fmt.Printf("\nUploading final reports to GCS: gs://%s/%s/\n", bucket, gcsPrefix)
	paths, err := uploader.UploadResults(ctx, result.RunID, result.StartTime, runDir)
	if err != nil {
		return fmt.Errorf("uploading final reports: %w", err)
	}
	for _, p := range paths {
		fmt.Printf("Uploaded: %s\n", p)
	}

	// Clean up intermediate files
	fmt.Printf("\nCleaning up runs/%s/...\n", runDate)
	if err := uploader.CleanupRun(ctx, runDate); err != nil {
		fmt.Printf("Warning: cleanup failed: %v\n", err)
	}

	fmt.Println("\n=== Finalize Complete ===")
	return nil
}

// waitForAllScaleToZero waits until all services have zero instances.
func waitForAllScaleToZero(ctx context.Context, cfg *config.Config, services []*gcp.GetServiceInfo) error {
	for _, svc := range services {
		scaleConfig := benchmark.ScaleToZeroConfig{
			ProjectID:    cfg.GCP.ProjectID,
			Region:       cfg.GCP.Region,
			ServiceName:  svc.ServiceName,
			Timeout:      cfg.Benchmark.ScaleToZeroTimeout,
			PollInterval: 30 * time.Second,
		}

		if err := benchmark.WaitForScaleToZero(ctx, scaleConfig); err != nil {
			return fmt.Errorf("%s: %w", svc.ServiceKey, err)
		}
	}
	return nil
}

// verifyScaledToZero checks that all services are at zero instances (non-blocking).
func verifyScaledToZero(ctx context.Context, cfg *config.Config, services []*gcp.GetServiceInfo) error {
	for _, svc := range services {
		scaleConfig := benchmark.ScaleToZeroConfig{
			ProjectID:   cfg.GCP.ProjectID,
			Region:      cfg.GCP.Region,
			ServiceName: svc.ServiceName,
		}

		isZero, err := benchmark.IsScaledToZero(ctx, scaleConfig)
		if err != nil {
			return fmt.Errorf("%s: %w", svc.ServiceKey, err)
		}
		if !isZero {
			return fmt.Errorf("%s is not at zero instances", svc.ServiceKey)
		}
	}
	return nil
}

// takeColdStartMeasurements takes cold start measurements for all services.
func takeColdStartMeasurements(ctx context.Context, cfg *config.Config, services []*gcp.GetServiceInfo, signer *signing.Signer, loggingClient *gcp.LoggingClient, tokens map[string]string) map[string]*benchmark.ColdStartResult {
	results := make(map[string]*benchmark.ColdStartResult)

	for _, svc := range services {
		fmt.Printf("  Measuring %s...\n", svc.ServiceKey)

		requestStartTime := time.Now()
		result, err := benchmark.MeasureColdStart(ctx, svc.URL, signer, tokens[svc.ServiceKey])
		if err != nil {
			fmt.Printf("    Error: %v\n", err)
		} else {
			fmt.Printf("    TTFB: %v\n", result.TTFB)
		}

		// Try to get container startup time
		if loggingClient != nil && result.Error == nil {
			metrics, err := loggingClient.WaitForStartupLog(ctx, svc.ServiceName, cfg.GCP.Region, requestStartTime, 30*time.Second)
			if err == nil && metrics.Found {
				result.ContainerStartup = metrics.ContainerStartupLatency
				fmt.Printf("    Container startup: %v\n", result.ContainerStartup)
			}
		}

		results[svc.ServiceKey] = result
	}

	return results
}

// runWarmTests runs warm request tests on all services.
func runWarmTests(ctx context.Context, cfg *config.Config, services []*gcp.GetServiceInfo, signer *signing.Signer, tokens map[string]string) map[string]*benchmark.WarmRequestStats {
	results := make(map[string]*benchmark.WarmRequestStats)

	for _, svc := range services {
		fmt.Printf("  Testing %s (%d requests, %d concurrency)...\n",
			svc.ServiceKey, cfg.Benchmark.WarmRequests, cfg.Benchmark.WarmConcurrency)

		warmCfg := benchmark.WarmRequestConfig{
			ServiceURL:   svc.URL,
			RequestCount: cfg.Benchmark.WarmRequests,
			Concurrency:  cfg.Benchmark.WarmConcurrency,
			Signer:       signer,
			RequestType:  benchmark.RequestTypePing,
			IDToken:      tokens[svc.ServiceKey],
		}

		stats, err := benchmark.RunWarmRequestBenchmark(ctx, warmCfg)
		if err != nil {
			fmt.Printf("    Error: %v\n", err)
		} else {
			fmt.Printf("    P50: %v, P95: %v (%.1f req/s)\n", stats.P50, stats.P95, stats.RequestsPerSecond)
		}

		results[svc.ServiceKey] = stats
	}

	return results
}

// buildBenchmarkResult builds a BenchmarkResult from adhoc measurements.
func buildBenchmarkResult(cfg *config.Config, services []*gcp.GetServiceInfo, coldResults map[string]*benchmark.ColdStartResult, warmResults map[string]*benchmark.WarmRequestStats) *benchmark.BenchmarkResult {
	result := &benchmark.BenchmarkResult{
		RunID:     "adhoc-" + time.Now().UTC().Format("20060102-150405"),
		StartTime: time.Now(),
		Config:    cfg,
		Services:  make(map[string]*benchmark.ServiceResult),
	}

	for _, svc := range services {
		svcResult := &benchmark.ServiceResult{
			ServiceName: svc.ServiceKey,
			ServiceURL:  svc.URL,
			Profile:     "default",
			Image:       cfg.ImageURI(svc.ServiceKey, "latest"),
		}

		// Add cold start result
		if cold, ok := coldResults[svc.ServiceKey]; ok {
			svcResult.ColdStart = &benchmark.ColdStartStats{
				Results: []benchmark.ColdStartResult{*cold},
			}
			if cold.Error == nil {
				svcResult.ColdStart.SuccessCount = 1
				svcResult.ColdStart.TTFBMin = cold.TTFB
				svcResult.ColdStart.TTFBMax = cold.TTFB
				svcResult.ColdStart.TTFBAvg = cold.TTFB
				svcResult.ColdStart.TTFBP50 = cold.TTFB
				svcResult.ColdStart.TTFBP95 = cold.TTFB
				svcResult.ColdStart.TTFBP99 = cold.TTFB
			} else {
				svcResult.ColdStart.FailureCount = 1
				svcResult.BenchmarkError = cold.Error
			}
		}

		// Add warm results
		if warm, ok := warmResults[svc.ServiceKey]; ok {
			svcResult.WarmRequest = warm
		}

		result.Services[svc.ServiceKey] = svcResult
	}

	result.EndTime = time.Now()
	return result
}

// consolidateReadings consolidates multiple readings into a single BenchmarkResult.
func consolidateReadings(cfg *config.Config, readings []*report.ReadingResult, services []*gcp.GetServiceInfo, warmResults map[string]*benchmark.WarmRequestStats) *benchmark.BenchmarkResult {
	result := &benchmark.BenchmarkResult{
		RunID:     readings[0].RunID,
		StartTime: readings[0].Timestamp,
		Config:    cfg,
		Services:  make(map[string]*benchmark.ServiceResult),
	}

	// Build service URL map
	serviceURLs := make(map[string]string)
	for _, svc := range services {
		serviceURLs[svc.ServiceKey] = svc.URL
	}

	// Aggregate cold start results from all readings
	for _, svc := range services {
		svcResult := &benchmark.ServiceResult{
			ServiceName: svc.ServiceKey,
			ServiceURL:  svc.URL,
			Profile:     "default",
			Image:       cfg.ImageURI(svc.ServiceKey, "latest"),
			ColdStart: &benchmark.ColdStartStats{
				Results: make([]benchmark.ColdStartResult, 0, len(readings)),
			},
		}

		// Collect cold start measurements from all readings
		for _, reading := range readings {
			if measurement, ok := reading.Services[svc.ServiceKey]; ok {
				coldResult := benchmark.ColdStartResult{
					TTFB:             measurement.TTFB,
					ContainerStartup: measurement.ContainerStartup,
					StatusCode:       measurement.StatusCode,
					Timestamp:        reading.Timestamp,
				}
				if measurement.Error != "" {
					coldResult.Error = fmt.Errorf("%s", measurement.Error)
					svcResult.ColdStart.FailureCount++
				} else {
					svcResult.ColdStart.SuccessCount++
				}
				svcResult.ColdStart.Results = append(svcResult.ColdStart.Results, coldResult)
			}
		}

		// Calculate stats
		svcResult.ColdStart.CalculateStats()

		// Add warm results
		if warm, ok := warmResults[svc.ServiceKey]; ok {
			svcResult.WarmRequest = warm
		}

		result.Services[svc.ServiceKey] = svcResult
	}

	result.EndTime = time.Now()
	return result
}

// ===== Legacy commands =====

func cmdDeploy(ctx context.Context) error {
	cfg, err := loadConfig()
	if err != nil {
		return err
	}

	runner, err := benchmark.NewRunner(ctx, cfg)
	if err != nil {
		return fmt.Errorf("creating runner: %w", err)
	}
	defer runner.Close()

	return runner.DeployOnly(ctx)
}

func cmdRun(ctx context.Context) error {
	cfg, err := loadConfig()
	if err != nil {
		return err
	}

	runner, err := benchmark.NewRunner(ctx, cfg)
	if err != nil {
		return fmt.Errorf("creating runner: %w", err)
	}
	defer runner.Close()

	// Run benchmarks (batch mode or sequential)
	var result *benchmark.BenchmarkResult
	if *batchMode {
		result, err = runner.RunBatch(ctx)
	} else {
		result, err = runner.Run(ctx)
	}
	if err != nil {
		return fmt.Errorf("running benchmark: %w", err)
	}

	// Create output directory
	runDir := filepath.Join(*outputDir, result.RunID)
	if err := os.MkdirAll(runDir, 0755); err != nil {
		return fmt.Errorf("creating output directory: %w", err)
	}

	// Write reports
	jsonPath := filepath.Join(runDir, "results.json")
	if err := report.WriteJSON(result, jsonPath); err != nil {
		return fmt.Errorf("writing JSON report: %w", err)
	}
	fmt.Printf("JSON report written to: %s\n", jsonPath)

	mdPath := filepath.Join(runDir, "results.md")
	if err := report.WriteMarkdown(result, mdPath); err != nil {
		return fmt.Errorf("writing Markdown report: %w", err)
	}
	fmt.Printf("Markdown report written to: %s\n", mdPath)

	// Write comparison report if local results provided
	if *localResults != "" {
		localData, err := report.LoadLocalResults(*localResults)
		if err != nil {
			fmt.Printf("Warning: could not load local results: %v\n", err)
		} else {
			comparison := report.Compare(localData, result)
			compPath := filepath.Join(runDir, "comparison.md")
			if err := report.WriteComparisonMarkdown(comparison, compPath); err != nil {
				return fmt.Errorf("writing comparison report: %w", err)
			}
			fmt.Printf("Comparison report written to: %s\n", compPath)
		}
	}

	// Upload to GCS if bucket specified (flag or env var)
	bucket := getGCSBucket()
	if bucket != "" {
		fmt.Printf("\nUploading results to GCS bucket: %s\n", bucket)
		uploader, err := report.NewGCSUploader(ctx, bucket)
		if err != nil {
			fmt.Printf("Warning: could not create GCS uploader: %v\n", err)
		} else {
			defer uploader.Close()
			paths, err := uploader.UploadResults(ctx, result.RunID, result.StartTime, runDir)
			if err != nil {
				fmt.Printf("Warning: GCS upload failed: %v\n", err)
			} else {
				for _, p := range paths {
					fmt.Printf("Uploaded: %s\n", p)
				}
			}
		}
	}

	// Cleanup
	fmt.Println("\nCleaning up resources...")
	if err := runner.Cleanup(ctx); err != nil {
		fmt.Printf("Warning: cleanup failed: %v\n", err)
	}

	return nil
}

func cmdCleanup(ctx context.Context) error {
	cfg, err := loadConfig()
	if err != nil {
		return err
	}

	runner, err := benchmark.NewRunner(ctx, cfg)
	if err != nil {
		return fmt.Errorf("creating runner: %w", err)
	}
	defer runner.Close()

	return runner.Cleanup(ctx)
}

func cmdReport(ctx context.Context) error {
	// This command generates reports from existing JSON results
	if flag.NArg() < 1 {
		return fmt.Errorf("usage: cloudrun-benchmark report <results.json>")
	}

	resultsPath := flag.Arg(0)

	// Load JSON results
	// For now, just print a message - full implementation would reload results
	fmt.Printf("Report generation from %s not yet implemented\n", resultsPath)
	fmt.Println("Use 'run' command to generate fresh results with reports")

	return nil
}

func init() {
	// Set default timeout for context
	_ = time.Hour
}

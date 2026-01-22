package benchmark

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/pmgledhill102/discord-bot-test-suite/tests/cloudrun/internal/gcp"
)

// DeployedService holds information about a deployed service for batch testing.
type DeployedService struct {
	Name        string
	FullName    string
	URL         string
	DeployTime  time.Duration
	DeployError error
}

// BatchResult contains results from a batch benchmark run.
type BatchResult struct {
	DeployedServices map[string]*DeployedService
	ColdStartResults map[string][]*ColdStartResult // service -> iterations
	WarmResults      map[string]*WarmRequestStats
}

// deployAll deploys all enabled services and returns their URLs.
func (r *Runner) deployAll(ctx context.Context) map[string]*DeployedService {
	results := make(map[string]*DeployedService)
	profile := r.config.GetProfile("default")

	for _, service := range r.config.Services.Enabled {
		fmt.Printf("Deploying %s...\n", service)
		deployStart := time.Now()

		deployConfig := gcp.DeployConfig{
			ServiceName:     service,
			RunID:           r.config.RunID,
			Image:           r.config.ImageURI(service, "latest"),
			CPU:             profile.CPU,
			Memory:          profile.Memory,
			MaxInstances:    profile.MaxInstances,
			Concurrency:     profile.Concurrency,
			ExecutionEnv:    profile.ExecutionEnv,
			StartupCPUBoost: profile.StartupCPUBoost,
			EnvVars: map[string]string{
				"DISCORD_PUBLIC_KEY":   r.signer.PublicKeyHex(),
				"PUBSUB_TOPIC":         r.pubsub.GetTopicName(gcp.PubSubConfig{RunID: r.config.RunID}),
				"GOOGLE_CLOUD_PROJECT": r.config.GCP.ProjectID,
			},
		}

		serviceURL, err := r.cloudrun.Deploy(ctx, deployConfig)
		deployTime := time.Since(deployStart)

		result := &DeployedService{
			Name:        service,
			FullName:    deployConfig.FullServiceName(),
			DeployTime:  deployTime,
			DeployError: err,
		}

		if err != nil {
			fmt.Printf("  Failed to deploy %s: %v\n", service, err)
		} else {
			result.URL = serviceURL
			fmt.Printf("  Deployed %s -> %s (took %v)\n", service, serviceURL, deployTime)
		}

		results[service] = result
	}

	return results
}

// waitAllScaleToZero waits until all deployed services have scaled to zero instances.
func (r *Runner) waitAllScaleToZero(ctx context.Context, services map[string]*DeployedService) error {
	fmt.Println("Waiting for all services to scale to zero...")

	// Use a WaitGroup to poll all services concurrently
	var wg sync.WaitGroup
	errors := make(chan error, len(services))

	for _, svc := range services {
		if svc.DeployError != nil || svc.URL == "" {
			continue // Skip failed deployments
		}

		wg.Add(1)
		go func(service *DeployedService) {
			defer wg.Done()

			scaleConfig := ScaleToZeroConfig{
				ProjectID:   r.config.GCP.ProjectID,
				Region:      r.config.GCP.Region,
				ServiceName: service.FullName,
				Timeout:     r.config.Benchmark.ScaleToZeroTimeout,
			}

			if err := WaitForScaleToZero(ctx, scaleConfig); err != nil {
				errors <- fmt.Errorf("%s: %w", service.Name, err)
			}
		}(svc)
	}

	// Wait for all goroutines to complete
	wg.Wait()
	close(errors)

	// Collect any errors
	var errs []error
	for err := range errors {
		errs = append(errs, err)
	}

	if len(errs) > 0 {
		return fmt.Errorf("scale to zero errors: %v", errs)
	}

	fmt.Println("All services scaled to zero")
	return nil
}

// testAllColdStart runs cold start test on each service sequentially.
// Services are tested sequentially to get accurate per-service cold start measurements.
func (r *Runner) testAllColdStart(ctx context.Context, services map[string]*DeployedService, iteration int) map[string]*ColdStartResult {
	results := make(map[string]*ColdStartResult)

	for _, svc := range services {
		if svc.DeployError != nil || svc.URL == "" {
			continue
		}

		fmt.Printf("  Cold start test: %s (iteration %d)...\n", svc.Name, iteration+1)

		// Record the time before making the request (for log queries)
		requestStartTime := time.Now()

		result, err := MeasureColdStart(ctx, svc.URL, r.signer)
		if err != nil {
			fmt.Printf("    Warning: cold start measurement failed for %s: %v\n", svc.Name, err)
		} else {
			fmt.Printf("    %s TTFB: %v\n", svc.Name, result.TTFB)
		}

		// Try to get container startup time from Cloud Logging
		if r.logging != nil && result.Error == nil {
			metrics, err := r.logging.WaitForStartupLog(
				ctx,
				svc.FullName,
				r.config.GCP.Region,
				requestStartTime,
				30*time.Second,
			)
			if err == nil && metrics.Found {
				result.ContainerStartup = metrics.ContainerStartupLatency
				fmt.Printf("    %s container startup: %v\n", svc.Name, result.ContainerStartup)
			}
		}

		results[svc.Name] = result
	}

	return results
}

// testAllWarm runs warm request tests on all services.
func (r *Runner) testAllWarm(ctx context.Context, services map[string]*DeployedService) map[string]*WarmRequestStats {
	results := make(map[string]*WarmRequestStats)

	for _, svc := range services {
		if svc.DeployError != nil || svc.URL == "" {
			continue
		}

		fmt.Printf("  Warm request test: %s (%d requests, %d concurrency)...\n",
			svc.Name, r.config.Benchmark.WarmRequests, r.config.Benchmark.WarmConcurrency)

		warmCfg := WarmRequestConfig{
			ServiceURL:   svc.URL,
			RequestCount: r.config.Benchmark.WarmRequests,
			Concurrency:  r.config.Benchmark.WarmConcurrency,
			Signer:       r.signer,
			RequestType:  RequestTypePing,
		}

		stats, err := RunWarmRequestBenchmark(ctx, warmCfg)
		if err != nil {
			fmt.Printf("    Warning: warm request test failed for %s: %v\n", svc.Name, err)
		} else {
			fmt.Printf("    %s P50: %v, P95: %v, P99: %v (%.1f req/s)\n",
				svc.Name, stats.P50, stats.P95, stats.P99, stats.RequestsPerSecond)
		}

		results[svc.Name] = stats
	}

	return results
}

// RunBatch executes benchmark in batch mode: deploy all → (wait → test all) × iterations.
// This is more efficient than the sequential approach when testing multiple services.
func (r *Runner) RunBatch(ctx context.Context) (*BenchmarkResult, error) {
	result := &BenchmarkResult{
		RunID:     r.config.RunID,
		StartTime: time.Now(),
		Config:    r.config,
		Services:  make(map[string]*ServiceResult),
	}

	fmt.Printf("Starting BATCH benchmark run: %s\n", r.config.RunID)
	fmt.Printf("Services: %v\n", r.config.Services.Enabled)
	fmt.Printf("Cold start iterations: %d\n", r.config.Benchmark.ColdStartIterations)

	// Setup Pub/Sub resources
	fmt.Println("\nSetting up Pub/Sub resources...")
	pubsubCfg := gcp.PubSubConfig{RunID: r.config.RunID}
	if err := r.pubsub.Setup(ctx, pubsubCfg); err != nil {
		return nil, fmt.Errorf("setting up Pub/Sub: %w", err)
	}

	// Phase 1: Deploy all services
	fmt.Println("\n=== Phase 1: Deploy All Services ===")
	deployedServices := r.deployAll(ctx)

	// Initialize service results
	for name, deployed := range deployedServices {
		result.Services[name] = &ServiceResult{
			ServiceName:        name,
			ServiceURL:         deployed.URL,
			Profile:            "default",
			DeploymentDuration: deployed.DeployTime,
			Image:              r.config.ImageURI(name, "latest"),
			DeployError:        deployed.DeployError,
			ColdStart: &ColdStartStats{
				Results: make([]ColdStartResult, 0, r.config.Benchmark.ColdStartIterations),
			},
		}
	}

	// Phase 2 & 3: For each iteration, wait for scale-to-zero then test all
	fmt.Printf("\n=== Phase 2 & 3: Cold Start Testing (%d iterations) ===\n", r.config.Benchmark.ColdStartIterations)
	for iter := 0; iter < r.config.Benchmark.ColdStartIterations; iter++ {
		fmt.Printf("\n--- Iteration %d/%d ---\n", iter+1, r.config.Benchmark.ColdStartIterations)

		// Skip scale-to-zero wait on first iteration (services start cold)
		if iter > 0 {
			if err := r.waitAllScaleToZero(ctx, deployedServices); err != nil {
				fmt.Printf("Warning: scale-to-zero wait failed: %v\n", err)
				// Continue anyway - we might still get useful measurements
			}
		}

		// Test all services
		coldResults := r.testAllColdStart(ctx, deployedServices, iter)

		// Aggregate results
		for name, coldResult := range coldResults {
			if svcResult, ok := result.Services[name]; ok && coldResult != nil {
				svcResult.ColdStart.Results = append(svcResult.ColdStart.Results, *coldResult)
				if coldResult.Error == nil {
					svcResult.ColdStart.SuccessCount++
				} else {
					svcResult.ColdStart.FailureCount++
				}
			}
		}
	}

	// Calculate cold start statistics
	for _, svcResult := range result.Services {
		if svcResult.ColdStart != nil {
			svcResult.ColdStart.CalculateStats()
		}
	}

	// Phase 4: Warm request tests (services should be warm after cold start tests)
	fmt.Println("\n=== Phase 4: Warm Request Testing ===")
	warmResults := r.testAllWarm(ctx, deployedServices)

	for name, warmStats := range warmResults {
		if svcResult, ok := result.Services[name]; ok {
			svcResult.WarmRequest = warmStats
		}
	}

	result.EndTime = time.Now()

	// Print summary
	fmt.Printf("\n=== Benchmark Complete ===\n")
	fmt.Printf("Total time: %v\n", result.EndTime.Sub(result.StartTime))
	fmt.Printf("Services tested: %d\n", len(result.Services))

	return result, nil
}

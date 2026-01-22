package benchmark

import (
	"context"
	"fmt"
	"time"

	"github.com/pmgledhill102/discord-bot-test-suite/tests/cloudrun/internal/config"
	"github.com/pmgledhill102/discord-bot-test-suite/tests/cloudrun/internal/gcp"
	"github.com/pmgledhill102/discord-bot-test-suite/tests/cloudrun/internal/signing"
)

// ServiceResult contains all benchmark results for a single service.
type ServiceResult struct {
	ServiceName string
	ServiceURL  string
	Profile     string

	// Deployment info
	DeploymentDuration time.Duration
	Image              string

	// Benchmark results
	ColdStart   *ColdStartStats
	WarmRequest *WarmRequestStats

	// Errors
	DeployError    error
	BenchmarkError error
}

// BenchmarkResult contains results for all services in a benchmark run.
type BenchmarkResult struct {
	RunID     string
	StartTime time.Time
	EndTime   time.Time
	Config    *config.Config

	Services map[string]*ServiceResult
}

// Runner orchestrates the benchmark execution.
type Runner struct {
	config        *config.Config
	cloudrun      *gcp.CloudRunClient
	pubsub        *gcp.PubSubClient
	logging       *gcp.LoggingClient
	signer        *signing.Signer
}

// NewRunner creates a new benchmark runner.
func NewRunner(ctx context.Context, cfg *config.Config) (*Runner, error) {
	cloudrun, err := gcp.NewCloudRunClient(ctx, cfg.GCP.ProjectID, cfg.GCP.Region)
	if err != nil {
		return nil, fmt.Errorf("creating Cloud Run client: %w", err)
	}

	pubsub, err := gcp.NewPubSubClient(ctx, cfg.GCP.ProjectID)
	if err != nil {
		return nil, fmt.Errorf("creating Pub/Sub client: %w", err)
	}

	logging, err := gcp.NewLoggingClient(ctx, cfg.GCP.ProjectID)
	if err != nil {
		return nil, fmt.Errorf("creating logging client: %w", err)
	}

	return &Runner{
		config:   cfg,
		cloudrun: cloudrun,
		pubsub:   pubsub,
		logging:  logging,
		signer:   signing.NewSigner(),
	}, nil
}

// Close releases resources held by the runner.
func (r *Runner) Close() error {
	if r.pubsub != nil {
		r.pubsub.Close()
	}
	if r.logging != nil {
		r.logging.Close()
	}
	return nil
}

// Run executes the full benchmark suite.
func (r *Runner) Run(ctx context.Context) (*BenchmarkResult, error) {
	result := &BenchmarkResult{
		RunID:     r.config.RunID,
		StartTime: time.Now(),
		Config:    r.config,
		Services:  make(map[string]*ServiceResult),
	}

	fmt.Printf("Starting benchmark run: %s\n", r.config.RunID)
	fmt.Printf("Services: %v\n", r.config.Services.Enabled)

	// Setup Pub/Sub resources
	fmt.Println("Setting up Pub/Sub resources...")
	pubsubCfg := gcp.PubSubConfig{RunID: r.config.RunID}
	if err := r.pubsub.Setup(ctx, pubsubCfg); err != nil {
		return nil, fmt.Errorf("setting up Pub/Sub: %w", err)
	}

	// Run benchmarks for each service
	for _, service := range r.config.Services.Enabled {
		fmt.Printf("\n=== Benchmarking %s ===\n", service)

		serviceResult := r.benchmarkService(ctx, service)
		result.Services[service] = serviceResult
	}

	result.EndTime = time.Now()

	return result, nil
}

// benchmarkService runs benchmarks for a single service.
func (r *Runner) benchmarkService(ctx context.Context, service string) *ServiceResult {
	result := &ServiceResult{
		ServiceName: service,
		Profile:     "default",
	}

	profile := r.config.GetProfile("default")

	// Deploy the service
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
			"PUBSUB_TOPIC":         r.pubsub.GetTopicPath(gcp.PubSubConfig{RunID: r.config.RunID}),
			"GOOGLE_CLOUD_PROJECT": r.config.GCP.ProjectID,
		},
	}

	serviceURL, err := r.cloudrun.Deploy(ctx, deployConfig)
	result.DeploymentDuration = time.Since(deployStart)
	result.Image = deployConfig.Image

	if err != nil {
		result.DeployError = err
		fmt.Printf("Failed to deploy %s: %v\n", service, err)
		return result
	}

	result.ServiceURL = serviceURL
	fmt.Printf("Deployed to: %s (took %v)\n", serviceURL, result.DeploymentDuration)

	// Run cold start benchmark
	fmt.Printf("Running cold start benchmark (%d iterations)...\n", r.config.Benchmark.ColdStartIterations)
	coldStartCfg := ColdStartConfig{
		ServiceURL:         serviceURL,
		ServiceName:        deployConfig.FullServiceName(),
		ProjectID:          r.config.GCP.ProjectID,
		Region:             r.config.GCP.Region,
		Iterations:         r.config.Benchmark.ColdStartIterations,
		ScaleToZeroTimeout: r.config.Benchmark.ScaleToZeroTimeout,
		Signer:             r.signer,
		LoggingClient:      r.logging,
	}

	coldStartStats, err := RunColdStartBenchmark(ctx, coldStartCfg)
	if err != nil {
		result.BenchmarkError = err
		fmt.Printf("Cold start benchmark failed: %v\n", err)
	} else {
		result.ColdStart = coldStartStats
		fmt.Printf("Cold start P50: %v, P95: %v, P99: %v\n",
			coldStartStats.TTFBP50, coldStartStats.TTFBP95, coldStartStats.TTFBP99)
	}

	// Run warm request benchmark
	fmt.Printf("Running warm request benchmark (%d requests, %d concurrency)...\n",
		r.config.Benchmark.WarmRequests, r.config.Benchmark.WarmConcurrency)

	warmCfg := WarmRequestConfig{
		ServiceURL:   serviceURL,
		RequestCount: r.config.Benchmark.WarmRequests,
		Concurrency:  r.config.Benchmark.WarmConcurrency,
		Signer:       r.signer,
		RequestType:  RequestTypePing,
	}

	warmStats, err := RunWarmRequestBenchmark(ctx, warmCfg)
	if err != nil {
		if result.BenchmarkError == nil {
			result.BenchmarkError = err
		}
		fmt.Printf("Warm request benchmark failed: %v\n", err)
	} else {
		result.WarmRequest = warmStats
		fmt.Printf("Warm request P50: %v, P95: %v, P99: %v (%.1f req/s)\n",
			warmStats.P50, warmStats.P95, warmStats.P99, warmStats.RequestsPerSecond)
	}

	return result
}

// Cleanup removes all resources created during the benchmark.
func (r *Runner) Cleanup(ctx context.Context) error {
	fmt.Println("Cleaning up resources...")

	// Delete Cloud Run services
	fmt.Println("Deleting Cloud Run services...")
	if err := r.cloudrun.DeleteByRunID(ctx, r.config.RunID); err != nil {
		fmt.Printf("Warning: failed to delete some services: %v\n", err)
	}

	// Delete Pub/Sub resources
	fmt.Println("Deleting Pub/Sub resources...")
	pubsubCfg := gcp.PubSubConfig{RunID: r.config.RunID}
	if err := r.pubsub.Cleanup(ctx, pubsubCfg); err != nil {
		fmt.Printf("Warning: failed to delete Pub/Sub resources: %v\n", err)
	}

	fmt.Println("Cleanup complete")
	return nil
}

// DeployOnly deploys all services without running benchmarks.
func (r *Runner) DeployOnly(ctx context.Context) error {
	fmt.Printf("Deploying services for run: %s\n", r.config.RunID)

	// Setup Pub/Sub resources
	pubsubCfg := gcp.PubSubConfig{RunID: r.config.RunID}
	if err := r.pubsub.Setup(ctx, pubsubCfg); err != nil {
		return fmt.Errorf("setting up Pub/Sub: %w", err)
	}

	profile := r.config.GetProfile("default")

	for _, service := range r.config.Services.Enabled {
		fmt.Printf("Deploying %s...\n", service)

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
				"PUBSUB_TOPIC":         r.pubsub.GetTopicPath(gcp.PubSubConfig{RunID: r.config.RunID}),
				"GOOGLE_CLOUD_PROJECT": r.config.GCP.ProjectID,
			},
		}

		serviceURL, err := r.cloudrun.Deploy(ctx, deployConfig)
		if err != nil {
			fmt.Printf("Failed to deploy %s: %v\n", service, err)
			continue
		}

		fmt.Printf("  %s -> %s\n", service, serviceURL)
	}

	return nil
}

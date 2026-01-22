// cloudrun-benchmark is a CLI tool for benchmarking Cloud Run cold start performance.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/pmgledhill102/discord-bot-test-suite/tests/cloudrun/internal/benchmark"
	"github.com/pmgledhill102/discord-bot-test-suite/tests/cloudrun/internal/config"
	"github.com/pmgledhill102/discord-bot-test-suite/tests/cloudrun/internal/report"
)

var (
	configPath   = flag.String("config", "configs/default.yaml", "Path to configuration file")
	outputDir    = flag.String("output", "results", "Output directory for results")
	services     = flag.String("services", "", "Comma-separated list of services to benchmark (overrides config)")
	localResults = flag.String("local-results", "", "Path to local benchmark results for comparison")
	batchMode    = flag.Bool("batch", false, "Run in batch mode (deploy all → wait → test all, more efficient)")
	gcsBucket    = flag.String("gcs-bucket", "", "GCS bucket for uploading results (env: GCS_RESULTS_BUCKET)")
)

func main() {
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: %s <command> [options]\n\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "Commands:\n")
		fmt.Fprintf(os.Stderr, "  deploy    Deploy services without running benchmarks\n")
		fmt.Fprintf(os.Stderr, "  run       Run the full benchmark suite\n")
		fmt.Fprintf(os.Stderr, "            Use --batch for efficient multi-service testing\n")
		fmt.Fprintf(os.Stderr, "  cleanup   Clean up resources for a specific run\n")
		fmt.Fprintf(os.Stderr, "  report    Generate reports from existing results\n")
		fmt.Fprintf(os.Stderr, "\nOptions:\n")
		flag.PrintDefaults()
	}

	if len(os.Args) < 2 {
		flag.Usage()
		os.Exit(1)
	}

	command := os.Args[1]
	os.Args = append(os.Args[:1], os.Args[2:]...)
	flag.Parse()

	ctx := context.Background()

	switch command {
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
	bucket := *gcsBucket
	if bucket == "" {
		bucket = os.Getenv("GCS_RESULTS_BUCKET")
	}
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

// Package config handles YAML configuration loading for Cloud Run benchmarks.
package config

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
	"time"

	"gopkg.in/yaml.v3"
)

// Config represents the complete benchmark configuration.
type Config struct {
	GCP       GCPConfig                `yaml:"gcp"`
	Profiles  map[string]ProfileConfig `yaml:"profiles"`
	Benchmark BenchmarkConfig          `yaml:"benchmark"`
	Services  ServicesConfig           `yaml:"services"`

	// Runtime fields (not from YAML)
	RunID string `yaml:"-"`
}

// GCPConfig contains GCP project settings.
type GCPConfig struct {
	ProjectID string `yaml:"project_id"`
	Region    string `yaml:"region"`
}

// ProfileConfig defines a Cloud Run deployment profile.
type ProfileConfig struct {
	CPU             string `yaml:"cpu"`
	Memory          string `yaml:"memory"`
	MaxInstances    int    `yaml:"max_instances"`
	Concurrency     int    `yaml:"concurrency"`
	ExecutionEnv    string `yaml:"execution_env"`    // "gen1" or "gen2"
	StartupCPUBoost bool   `yaml:"startup_cpu_boost"`
}

// BenchmarkConfig contains benchmark execution parameters.
type BenchmarkConfig struct {
	ColdStartIterations  int           `yaml:"cold_start_iterations"`
	ScaleToZeroTimeout   time.Duration `yaml:"scale_to_zero_timeout"`
	WarmRequests         int           `yaml:"warm_requests"`
	WarmConcurrency      int           `yaml:"warm_concurrency"`
}

// ServicesConfig defines which services to benchmark.
type ServicesConfig struct {
	Enabled []string `yaml:"enabled"`
}

// Load reads and parses a YAML configuration file.
func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading config file: %w", err)
	}

	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parsing config file: %w", err)
	}

	// Generate a unique run ID
	cfg.RunID = generateRunID()

	// Apply defaults
	cfg.applyDefaults()

	// Validate configuration
	if err := cfg.validate(); err != nil {
		return nil, fmt.Errorf("validating config: %w", err)
	}

	return &cfg, nil
}

// generateRunID creates a unique 8-character hex string for this benchmark run.
func generateRunID() string {
	b := make([]byte, 4)
	if _, err := rand.Read(b); err != nil {
		// Fallback to timestamp if random fails
		return fmt.Sprintf("%08x", time.Now().UnixNano()&0xFFFFFFFF)
	}
	return hex.EncodeToString(b)
}

// applyDefaults sets default values for unset configuration options.
func (c *Config) applyDefaults() {
	// Environment variables take precedence over config file values
	if envProject := os.Getenv("PROJECT_ID"); envProject != "" {
		c.GCP.ProjectID = envProject
	}
	if envRegion := os.Getenv("REGION"); envRegion != "" {
		c.GCP.Region = envRegion
	}

	// Fall back to default region if still unset
	if c.GCP.Region == "" {
		c.GCP.Region = "us-central1"
	}

	if c.Benchmark.ColdStartIterations == 0 {
		c.Benchmark.ColdStartIterations = 5
	}

	if c.Benchmark.ScaleToZeroTimeout == 0 {
		c.Benchmark.ScaleToZeroTimeout = 15 * time.Minute
	}

	if c.Benchmark.WarmRequests == 0 {
		c.Benchmark.WarmRequests = 100
	}

	if c.Benchmark.WarmConcurrency == 0 {
		c.Benchmark.WarmConcurrency = 10
	}

	// Ensure default profile exists
	if c.Profiles == nil {
		c.Profiles = make(map[string]ProfileConfig)
	}

	if _, ok := c.Profiles["default"]; !ok {
		c.Profiles["default"] = ProfileConfig{
			CPU:             "1",
			Memory:          "512Mi",
			MaxInstances:    1,
			Concurrency:     80,
			ExecutionEnv:    "gen2",
			StartupCPUBoost: true,
		}
	}
}

// validate checks that the configuration is valid.
func (c *Config) validate() error {
	if c.GCP.ProjectID == "" {
		return fmt.Errorf("gcp.project_id is required")
	}

	if len(c.Services.Enabled) == 0 {
		return fmt.Errorf("services.enabled must contain at least one service")
	}

	for name, profile := range c.Profiles {
		if profile.ExecutionEnv != "" && profile.ExecutionEnv != "gen1" && profile.ExecutionEnv != "gen2" {
			return fmt.Errorf("profile %q: execution_env must be 'gen1' or 'gen2'", name)
		}
	}

	return nil
}

// GetProfile returns the named profile, falling back to "default" if not found.
func (c *Config) GetProfile(name string) ProfileConfig {
	if profile, ok := c.Profiles[name]; ok {
		return profile
	}
	return c.Profiles["default"]
}

// ServiceName returns the full Cloud Run service name for a given service.
// Format: discord-{service}-{runID}
func (c *Config) ServiceName(service string) string {
	return fmt.Sprintf("discord-%s-%s", service, c.RunID)
}

// TopicName returns the Pub/Sub topic name for this run.
// Format: discord-benchmark-{runID}
func (c *Config) TopicName() string {
	return fmt.Sprintf("discord-benchmark-%s", c.RunID)
}

// SubscriptionName returns the Pub/Sub subscription name for this run.
// Format: discord-benchmark-{runID}-sub
func (c *Config) SubscriptionName() string {
	return fmt.Sprintf("discord-benchmark-%s-sub", c.RunID)
}

// ImageURI returns the full Artifact Registry image URI for a service.
func (c *Config) ImageURI(service, tag string) string {
	return fmt.Sprintf("%s-docker.pkg.dev/%s/discord-services/%s:%s",
		c.GCP.Region, c.GCP.ProjectID, service, tag)
}

// UnmarshalYAML implements custom unmarshaling for duration fields.
func (b *BenchmarkConfig) UnmarshalYAML(unmarshal func(interface{}) error) error {
	type rawBenchmarkConfig struct {
		ColdStartIterations int    `yaml:"cold_start_iterations"`
		ScaleToZeroTimeout  string `yaml:"scale_to_zero_timeout"`
		WarmRequests        int    `yaml:"warm_requests"`
		WarmConcurrency     int    `yaml:"warm_concurrency"`
	}

	var raw rawBenchmarkConfig
	if err := unmarshal(&raw); err != nil {
		return err
	}

	b.ColdStartIterations = raw.ColdStartIterations
	b.WarmRequests = raw.WarmRequests
	b.WarmConcurrency = raw.WarmConcurrency

	if raw.ScaleToZeroTimeout != "" {
		d, err := time.ParseDuration(raw.ScaleToZeroTimeout)
		if err != nil {
			return fmt.Errorf("parsing scale_to_zero_timeout: %w", err)
		}
		b.ScaleToZeroTimeout = d
	}

	return nil
}

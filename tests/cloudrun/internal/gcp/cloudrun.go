package gcp

import (
	"context"
	"fmt"
	"strings"
	"time"

	"google.golang.org/api/run/v2"
)

// CloudRunClient provides methods for managing Cloud Run services.
type CloudRunClient struct {
	service   *run.Service
	projectID string
	region    string
}

// NewCloudRunClient creates a new Cloud Run client.
func NewCloudRunClient(ctx context.Context, projectID, region string) (*CloudRunClient, error) {
	svc, err := NewRunService(ctx)
	if err != nil {
		return nil, err
	}

	return &CloudRunClient{
		service:   svc,
		projectID: projectID,
		region:    region,
	}, nil
}

// DeployConfig contains configuration for deploying a Cloud Run service.
type DeployConfig struct {
	ServiceName     string            // Base name, e.g., "go-gin"
	RunID           string            // Unique run identifier, e.g., "a1b2c3"
	Image           string            // Full image URI
	CPU             string            // e.g., "1", "2"
	Memory          string            // e.g., "512Mi", "1Gi"
	MaxInstances    int               // Maximum number of instances
	Concurrency     int               // Max concurrent requests per instance
	ExecutionEnv    string            // "gen1" or "gen2"
	StartupCPUBoost bool              // Enable startup CPU boost
	EnvVars         map[string]string // Environment variables
}

// FullServiceName returns the complete service name: discord-{ServiceName}-{RunID}
func (c *DeployConfig) FullServiceName() string {
	return fmt.Sprintf("discord-%s-%s", c.ServiceName, c.RunID)
}

// Deploy deploys a service to Cloud Run and waits for it to be ready.
func (c *CloudRunClient) Deploy(ctx context.Context, cfg DeployConfig) (string, error) {
	fullName := cfg.FullServiceName()
	parent := fmt.Sprintf("projects/%s/locations/%s", c.projectID, c.region)

	// Build environment variables
	var envVars []*run.GoogleCloudRunV2EnvVar
	for k, v := range cfg.EnvVars {
		envVars = append(envVars, &run.GoogleCloudRunV2EnvVar{
			Name:  k,
			Value: v,
		})
	}

	// Determine execution environment
	executionEnv := "EXECUTION_ENVIRONMENT_GEN2"
	if cfg.ExecutionEnv == "gen1" {
		executionEnv = "EXECUTION_ENVIRONMENT_GEN1"
	}

	// Build the service definition
	service := &run.GoogleCloudRunV2Service{
		LaunchStage: "GA",
		Template: &run.GoogleCloudRunV2RevisionTemplate{
			Containers: []*run.GoogleCloudRunV2Container{
				{
					Image: cfg.Image,
					Resources: &run.GoogleCloudRunV2ResourceRequirements{
						Limits: map[string]string{
							"cpu":    cfg.CPU,
							"memory": cfg.Memory,
						},
						CpuIdle:         true, // Allow CPU to be throttled when idle
						StartupCpuBoost: cfg.StartupCPUBoost,
					},
					Env: envVars,
					Ports: []*run.GoogleCloudRunV2ContainerPort{
						{ContainerPort: 8080},
					},
				},
			},
			ExecutionEnvironment: executionEnv,
			MaxInstanceRequestConcurrency: int64(cfg.Concurrency),
			Scaling: &run.GoogleCloudRunV2RevisionScaling{
				MinInstanceCount: 0, // Allow scale to zero for cold start testing
				MaxInstanceCount: int64(cfg.MaxInstances),
			},
		},
	}

	// Check if service already exists
	existing, err := c.getService(ctx, fullName)
	var op *run.GoogleLongrunningOperation
	if err == nil && existing != nil {
		// Update existing service
		op, err = c.service.Projects.Locations.Services.Patch(
			fmt.Sprintf("%s/services/%s", parent, fullName),
			service,
		).Context(ctx).Do()
		if err != nil {
			return "", fmt.Errorf("updating service %s: %w", fullName, err)
		}
	} else {
		// Create new service
		// Note: service.Name must be empty for Create - the name is passed via ServiceId()
		op, err = c.service.Projects.Locations.Services.Create(parent, service).
			ServiceId(fullName).
			Context(ctx).
			Do()
		if err != nil {
			return "", fmt.Errorf("creating service %s: %w", fullName, err)
		}
	}

	// Wait for the operation to complete
	if err := c.waitForOperation(ctx, op.Name, 5*time.Minute); err != nil {
		return "", fmt.Errorf("waiting for operation: %w", err)
	}

	// Wait for service to be ready (should be quick after operation completes)
	serviceURL, err := c.WaitForReady(ctx, fullName, 2*time.Minute)
	if err != nil {
		return "", err
	}

	// Make the service publicly accessible (allow unauthenticated)
	if err := c.allowUnauthenticated(ctx, fullName); err != nil {
		return "", fmt.Errorf("setting IAM policy: %w", err)
	}

	return serviceURL, nil
}

// allowUnauthenticated sets IAM policy to allow unauthenticated access.
func (c *CloudRunClient) allowUnauthenticated(ctx context.Context, serviceName string) error {
	resource := fmt.Sprintf("projects/%s/locations/%s/services/%s", c.projectID, c.region, serviceName)

	policy := &run.GoogleIamV1Policy{
		Bindings: []*run.GoogleIamV1Binding{
			{
				Role:    "roles/run.invoker",
				Members: []string{"allUsers"},
			},
		},
	}

	_, err := c.service.Projects.Locations.Services.SetIamPolicy(
		resource,
		&run.GoogleIamV1SetIamPolicyRequest{Policy: policy},
	).Context(ctx).Do()

	return err
}

// getService retrieves a service by name.
func (c *CloudRunClient) getService(ctx context.Context, serviceName string) (*run.GoogleCloudRunV2Service, error) {
	name := fmt.Sprintf("projects/%s/locations/%s/services/%s", c.projectID, c.region, serviceName)
	return c.service.Projects.Locations.Services.Get(name).Context(ctx).Do()
}

// waitForOperation polls a long-running operation until it completes.
func (c *CloudRunClient) waitForOperation(ctx context.Context, operationName string, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)

	for time.Now().Before(deadline) {
		op, err := c.service.Projects.Locations.Operations.Get(operationName).Context(ctx).Do()
		if err != nil {
			return fmt.Errorf("getting operation status: %w", err)
		}

		if op.Done {
			// Check if the operation failed
			if op.Error != nil {
				return fmt.Errorf("operation failed: %s (code %d)", op.Error.Message, op.Error.Code)
			}
			return nil
		}

		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(3 * time.Second):
			continue
		}
	}

	return fmt.Errorf("timeout waiting for operation %s", operationName)
}

// WaitForReady waits for a service to be ready and returns its URL.
func (c *CloudRunClient) WaitForReady(ctx context.Context, serviceName string, timeout time.Duration) (string, error) {
	deadline := time.Now().Add(timeout)

	for time.Now().Before(deadline) {
		svc, err := c.getService(ctx, serviceName)
		if err != nil {
			return "", fmt.Errorf("getting service status: %w", err)
		}

		// Check terminalCondition for service readiness
		if svc.TerminalCondition != nil {
			if svc.TerminalCondition.State == "CONDITION_SUCCEEDED" {
				return svc.Uri, nil
			}
			// If terminal state is failed, return error immediately
			if svc.TerminalCondition.State == "CONDITION_FAILED" {
				return "", fmt.Errorf("service failed: %s", svc.TerminalCondition.Message)
			}
		}

		select {
		case <-ctx.Done():
			return "", ctx.Err()
		case <-time.After(5 * time.Second):
			continue
		}
	}

	return "", fmt.Errorf("timeout waiting for service %s to be ready", serviceName)
}

// Delete deletes a Cloud Run service.
func (c *CloudRunClient) Delete(ctx context.Context, serviceName string) error {
	name := fmt.Sprintf("projects/%s/locations/%s/services/%s", c.projectID, c.region, serviceName)
	_, err := c.service.Projects.Locations.Services.Delete(name).Context(ctx).Do()
	if err != nil {
		return fmt.Errorf("deleting service %s: %w", serviceName, err)
	}
	return nil
}

// DeleteByRunID deletes all services for a specific run ID.
func (c *CloudRunClient) DeleteByRunID(ctx context.Context, runID string) error {
	services, err := c.ListByPrefix(ctx, "discord-")
	if err != nil {
		return err
	}

	var errs []error
	for _, svc := range services {
		if strings.HasSuffix(svc, "-"+runID) {
			if err := c.Delete(ctx, svc); err != nil {
				errs = append(errs, err)
			}
		}
	}

	if len(errs) > 0 {
		return fmt.Errorf("failed to delete %d services: %v", len(errs), errs)
	}
	return nil
}

// ListByPrefix returns all service names matching the given prefix.
func (c *CloudRunClient) ListByPrefix(ctx context.Context, prefix string) ([]string, error) {
	parent := fmt.Sprintf("projects/%s/locations/%s", c.projectID, c.region)

	var serviceNames []string
	pageToken := ""

	for {
		call := c.service.Projects.Locations.Services.List(parent).Context(ctx)
		if pageToken != "" {
			call = call.PageToken(pageToken)
		}

		resp, err := call.Do()
		if err != nil {
			return nil, fmt.Errorf("listing services: %w", err)
		}

		for _, svc := range resp.Services {
			// Extract service name from full resource name
			parts := strings.Split(svc.Name, "/")
			name := parts[len(parts)-1]
			if strings.HasPrefix(name, prefix) {
				serviceNames = append(serviceNames, name)
			}
		}

		if resp.NextPageToken == "" {
			break
		}
		pageToken = resp.NextPageToken
	}

	return serviceNames, nil
}

// GetInstanceCount returns the current number of running instances for a service.
func (c *CloudRunClient) GetInstanceCount(ctx context.Context, serviceName string) (int, error) {
	svc, err := c.getService(ctx, serviceName)
	if err != nil {
		return 0, err
	}

	// The instance count is not directly exposed in the v2 API
	// We need to check the traffic status or use monitoring API
	// For now, return 0 if there's no recent activity indicator

	// Check if the service has been recently accessed by looking at conditions
	for _, condition := range svc.Conditions {
		if condition.Type == "RoutesReady" && condition.State == "CONDITION_SUCCEEDED" {
			// Service is ready, but we can't directly get instance count
			// Return -1 to indicate unknown (caller should use scale-to-zero detection)
			return -1, nil
		}
	}

	return 0, nil
}

// GetServiceURL returns the URL for a deployed service.
func (c *CloudRunClient) GetServiceURL(ctx context.Context, serviceName string) (string, error) {
	svc, err := c.getService(ctx, serviceName)
	if err != nil {
		return "", err
	}
	return svc.Uri, nil
}

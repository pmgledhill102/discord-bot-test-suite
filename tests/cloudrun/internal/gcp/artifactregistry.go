package gcp

import (
	"context"
	"fmt"
	"strings"

	artifactregistry "google.golang.org/api/artifactregistry/v1"
)

// ArtifactRegistryClient provides methods for querying Artifact Registry.
type ArtifactRegistryClient struct {
	service   *artifactregistry.Service
	projectID string
	region    string
}

// NewArtifactRegistryClient creates a new Artifact Registry client.
func NewArtifactRegistryClient(ctx context.Context, projectID, region string) (*ArtifactRegistryClient, error) {
	svc, err := artifactregistry.NewService(ctx)
	if err != nil {
		return nil, fmt.Errorf("creating artifact registry service: %w", err)
	}

	return &ArtifactRegistryClient{
		service:   svc,
		projectID: projectID,
		region:    region,
	}, nil
}

// GetImageSize returns the size of a Docker image in bytes.
// imageURI should be in the format: REGION-docker.pkg.dev/PROJECT/REPO/IMAGE:TAG
func (c *ArtifactRegistryClient) GetImageSize(ctx context.Context, imageURI string) (int64, error) {
	// Parse image URI to extract components
	// Format: europe-west1-docker.pkg.dev/project-id/discord-services/go-gin:latest
	name, err := parseImageURIToResourceName(imageURI)
	if err != nil {
		return 0, fmt.Errorf("parsing image URI: %w", err)
	}

	// Get the docker image metadata
	img, err := c.service.Projects.Locations.Repositories.DockerImages.Get(name).Context(ctx).Do()
	if err != nil {
		return 0, fmt.Errorf("getting image metadata: %w", err)
	}

	return img.ImageSizeBytes, nil
}

// parseImageURIToResourceName converts an image URI to an Artifact Registry resource name.
// Input:  europe-west1-docker.pkg.dev/project-id/discord-services/go-gin:latest
// Output: projects/project-id/locations/europe-west1/repositories/discord-services/dockerImages/go-gin:latest
func parseImageURIToResourceName(imageURI string) (string, error) {
	// Remove the docker.pkg.dev suffix from region
	// europe-west1-docker.pkg.dev -> europe-west1
	parts := strings.SplitN(imageURI, "/", 4)
	if len(parts) < 4 {
		return "", fmt.Errorf("invalid image URI format: %s", imageURI)
	}

	hostParts := strings.Split(parts[0], "-docker.pkg.dev")
	if len(hostParts) != 2 {
		return "", fmt.Errorf("invalid host format: %s", parts[0])
	}
	region := hostParts[0]

	project := parts[1]
	repo := parts[2]
	imageAndTag := parts[3]

	// The resource name format for dockerImages uses the image path with tag
	// Note: The API expects the image name to be URL-encoded, but the Go client handles this
	return fmt.Sprintf("projects/%s/locations/%s/repositories/%s/dockerImages/%s",
		project, region, repo, imageAndTag), nil
}

// FormatImageSize formats image size in bytes to a human-readable string.
func FormatImageSize(bytes int64) string {
	if bytes == 0 {
		return "-"
	}

	const (
		KB = 1024
		MB = KB * 1024
		GB = MB * 1024
	)

	switch {
	case bytes >= GB:
		return fmt.Sprintf("%.1f GB", float64(bytes)/float64(GB))
	case bytes >= MB:
		return fmt.Sprintf("%.1f MB", float64(bytes)/float64(MB))
	case bytes >= KB:
		return fmt.Sprintf("%.1f KB", float64(bytes)/float64(KB))
	default:
		return fmt.Sprintf("%d B", bytes)
	}
}

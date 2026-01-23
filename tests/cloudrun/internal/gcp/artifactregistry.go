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
	region, project, repo, imageName, tag, err := parseImageURI(imageURI)
	if err != nil {
		return 0, fmt.Errorf("parsing image URI: %w", err)
	}

	// Build parent path for listing docker images
	parent := fmt.Sprintf("projects/%s/locations/%s/repositories/%s", project, region, repo)

	// List docker images and find the one with our tag
	// We need to iterate because the API uses sha256 digests as the primary identifier
	var totalSize int64
	err = c.service.Projects.Locations.Repositories.DockerImages.List(parent).
		Context(ctx).
		Pages(ctx, func(resp *artifactregistry.ListDockerImagesResponse) error {
			for _, img := range resp.DockerImages {
				// Check if this image has our tag
				for _, imgTag := range img.Tags {
					if imgTag == tag {
						// Found the tagged image - now we need to get the actual size
						// The tagged image might be a manifest list (multi-arch)
						// Try to get size from this image or its referenced images
						if img.ImageSizeBytes > 0 {
							totalSize = img.ImageSizeBytes
							return nil
						}
						// For manifest lists, we need to find the amd64 image
						// Look for images with same base name
						break
					}
				}
				// Also check if this is a platform-specific image under the same name
				// These have the actual size
				if img.ImageSizeBytes > 0 && strings.Contains(img.Name, "/"+imageName+"@") {
					// Check if this is a linux/amd64 image (most common for Cloud Run)
					// The name format is: .../dockerImages/IMAGE@sha256:...
					totalSize = img.ImageSizeBytes
					// Don't return yet - keep looking for a better match
				}
			}
			return nil
		})

	if err != nil {
		return 0, fmt.Errorf("listing docker images: %w", err)
	}

	if totalSize == 0 {
		return 0, fmt.Errorf("image not found or size not available: %s", imageURI)
	}

	return totalSize, nil
}

// parseImageURI extracts components from an image URI.
// Input:  europe-west1-docker.pkg.dev/project-id/discord-services/go-gin:latest
// Returns: region, project, repo, image, tag
func parseImageURI(imageURI string) (region, project, repo, image, tag string, err error) {
	parts := strings.SplitN(imageURI, "/", 4)
	if len(parts) < 4 {
		return "", "", "", "", "", fmt.Errorf("invalid image URI format: %s", imageURI)
	}

	// Parse host to extract region
	// europe-west1-docker.pkg.dev -> europe-west1
	hostParts := strings.Split(parts[0], "-docker.pkg.dev")
	if len(hostParts) != 2 {
		return "", "", "", "", "", fmt.Errorf("invalid host format: %s", parts[0])
	}
	region = hostParts[0]
	project = parts[1]
	repo = parts[2]

	// Parse image:tag
	imageAndTag := parts[3]
	if idx := strings.LastIndex(imageAndTag, ":"); idx != -1 {
		image = imageAndTag[:idx]
		tag = imageAndTag[idx+1:]
	} else {
		image = imageAndTag
		tag = "latest"
	}

	return region, project, repo, image, tag, nil
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

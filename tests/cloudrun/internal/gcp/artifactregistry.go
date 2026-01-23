package gcp

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	"golang.org/x/oauth2/google"
)

// ArtifactRegistryClient provides methods for querying Artifact Registry.
type ArtifactRegistryClient struct {
	projectID  string
	region     string
	httpClient *http.Client
}

// NewArtifactRegistryClient creates a new Artifact Registry client.
func NewArtifactRegistryClient(ctx context.Context, projectID, region string) (*ArtifactRegistryClient, error) {
	// Create an HTTP client with default credentials for Docker Registry API
	client, err := google.DefaultClient(ctx, "https://www.googleapis.com/auth/cloud-platform")
	if err != nil {
		return nil, fmt.Errorf("creating authenticated HTTP client: %w", err)
	}

	return &ArtifactRegistryClient{
		projectID:  projectID,
		region:     region,
		httpClient: client,
	}, nil
}

// dockerManifest represents a Docker image manifest (v2 schema 2).
type dockerManifest struct {
	SchemaVersion int    `json:"schemaVersion"`
	MediaType     string `json:"mediaType"`

	// For manifest lists (multi-arch images)
	Manifests []manifestDescriptor `json:"manifests,omitempty"`

	// For single-arch images
	Config manifestLayer   `json:"config,omitempty"`
	Layers []manifestLayer `json:"layers,omitempty"`
}

// manifestDescriptor describes a platform-specific manifest in a manifest list.
type manifestDescriptor struct {
	MediaType string `json:"mediaType"`
	Size      int64  `json:"size"`
	Digest    string `json:"digest"`
	Platform  struct {
		Architecture string `json:"architecture"`
		OS           string `json:"os"`
	} `json:"platform"`
}

// manifestLayer describes a layer or config blob.
type manifestLayer struct {
	MediaType string `json:"mediaType"`
	Size      int64  `json:"size"`
	Digest    string `json:"digest"`
}

// GetImageSize returns the size of a Docker image in bytes.
// imageURI should be in the format: REGION-docker.pkg.dev/PROJECT/REPO/IMAGE:TAG
// For multi-arch images, returns the size of the linux/amd64 platform image.
func (c *ArtifactRegistryClient) GetImageSize(ctx context.Context, imageURI string) (int64, error) {
	region, project, repo, imageName, tag, err := parseImageURI(imageURI)
	if err != nil {
		return 0, fmt.Errorf("parsing image URI: %w", err)
	}

	// Fetch the manifest for the tagged image
	manifest, err := c.fetchManifest(ctx, region, project, repo, imageName, tag)
	if err != nil {
		return 0, fmt.Errorf("fetching manifest: %w", err)
	}

	// Check if this is a manifest list (multi-arch image)
	if isManifestList(manifest.MediaType) {
		// Find the linux/amd64 manifest
		var amd64Digest string
		for _, m := range manifest.Manifests {
			if m.Platform.OS == "linux" && m.Platform.Architecture == "amd64" {
				amd64Digest = m.Digest
				break
			}
		}
		if amd64Digest == "" {
			// Fall back to first manifest if no linux/amd64
			if len(manifest.Manifests) > 0 {
				amd64Digest = manifest.Manifests[0].Digest
			} else {
				return 0, fmt.Errorf("no platform manifests found in manifest list")
			}
		}

		// Fetch the platform-specific manifest
		manifest, err = c.fetchManifest(ctx, region, project, repo, imageName, amd64Digest)
		if err != nil {
			return 0, fmt.Errorf("fetching platform manifest: %w", err)
		}
	}

	// Calculate total size from config + layers
	var totalSize int64
	totalSize += manifest.Config.Size
	for _, layer := range manifest.Layers {
		totalSize += layer.Size
	}

	if totalSize == 0 {
		return 0, fmt.Errorf("could not determine image size")
	}

	return totalSize, nil
}

// fetchManifest fetches a Docker manifest from Artifact Registry using the Registry API v2.
func (c *ArtifactRegistryClient) fetchManifest(ctx context.Context, region, project, repo, image, reference string) (*dockerManifest, error) {
	// Docker Registry API v2 endpoint
	// https://REGION-docker.pkg.dev/v2/PROJECT/REPO/IMAGE/manifests/TAG_OR_DIGEST
	url := fmt.Sprintf("https://%s-docker.pkg.dev/v2/%s/%s/%s/manifests/%s",
		region, project, repo, image, reference)

	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("creating request: %w", err)
	}

	// Accept both manifest list and single manifest formats
	req.Header.Set("Accept", strings.Join([]string{
		"application/vnd.docker.distribution.manifest.list.v2+json",
		"application/vnd.oci.image.index.v1+json",
		"application/vnd.docker.distribution.manifest.v2+json",
		"application/vnd.oci.image.manifest.v1+json",
	}, ", "))

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetching manifest: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("registry returned %d: %s", resp.StatusCode, string(body))
	}

	var manifest dockerManifest
	if err := json.NewDecoder(resp.Body).Decode(&manifest); err != nil {
		return nil, fmt.Errorf("decoding manifest: %w", err)
	}

	// Set media type from response header if not in body
	if manifest.MediaType == "" {
		manifest.MediaType = resp.Header.Get("Content-Type")
	}

	return &manifest, nil
}

// isManifestList returns true if the media type indicates a manifest list.
func isManifestList(mediaType string) bool {
	return strings.Contains(mediaType, "manifest.list") ||
		strings.Contains(mediaType, "image.index")
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

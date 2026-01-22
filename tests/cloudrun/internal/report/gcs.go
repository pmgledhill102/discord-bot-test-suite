package report

import (
	"context"
	"fmt"
	"io"
	"os"
	"path"
	"time"

	"cloud.google.com/go/storage"
)

// GCSUploader uploads benchmark results to Google Cloud Storage.
type GCSUploader struct {
	client     *storage.Client
	bucketName string
}

// NewGCSUploader creates a new GCS uploader.
func NewGCSUploader(ctx context.Context, bucketName string) (*GCSUploader, error) {
	client, err := storage.NewClient(ctx)
	if err != nil {
		return nil, fmt.Errorf("creating storage client: %w", err)
	}

	return &GCSUploader{
		client:     client,
		bucketName: bucketName,
	}, nil
}

// Close closes the GCS client.
func (u *GCSUploader) Close() error {
	return u.client.Close()
}

// UploadResults uploads benchmark result files to GCS.
// Files are organized as: YYYY/MM/DD/<run-id>/results.json, results.md
func (u *GCSUploader) UploadResults(ctx context.Context, runID string, timestamp time.Time, localDir string) ([]string, error) {
	// Build the GCS path prefix: YYYY/MM/DD/<run-id>/
	datePath := timestamp.UTC().Format("2006/01/02")
	prefix := path.Join(datePath, runID)

	// Files to upload
	files := []string{"results.json", "results.md"}
	var uploadedPaths []string

	for _, filename := range files {
		localPath := path.Join(localDir, filename)

		// Check if file exists
		if _, err := os.Stat(localPath); os.IsNotExist(err) {
			continue
		}

		gcsPath := path.Join(prefix, filename)

		if err := u.uploadFile(ctx, localPath, gcsPath); err != nil {
			return uploadedPaths, fmt.Errorf("uploading %s: %w", filename, err)
		}

		fullPath := fmt.Sprintf("gs://%s/%s", u.bucketName, gcsPath)
		uploadedPaths = append(uploadedPaths, fullPath)
	}

	return uploadedPaths, nil
}

// uploadFile uploads a single file to GCS.
func (u *GCSUploader) uploadFile(ctx context.Context, localPath, gcsPath string) error {
	// Open local file
	f, err := os.Open(localPath)
	if err != nil {
		return fmt.Errorf("opening file: %w", err)
	}
	defer f.Close()

	// Create GCS object writer
	obj := u.client.Bucket(u.bucketName).Object(gcsPath)
	writer := obj.NewWriter(ctx)

	// Set content type based on extension
	switch path.Ext(gcsPath) {
	case ".json":
		writer.ContentType = "application/json"
	case ".md":
		writer.ContentType = "text/markdown"
	default:
		writer.ContentType = "text/plain"
	}

	// Copy data
	if _, err := io.Copy(writer, f); err != nil {
		writer.Close()
		return fmt.Errorf("writing to GCS: %w", err)
	}

	// Close writer to finalize upload
	if err := writer.Close(); err != nil {
		return fmt.Errorf("finalizing upload: %w", err)
	}

	return nil
}

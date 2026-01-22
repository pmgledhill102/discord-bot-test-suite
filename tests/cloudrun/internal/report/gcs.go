package report

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"

	"cloud.google.com/go/storage"
	"google.golang.org/api/iterator"

	"github.com/pmgledhill102/discord-bot-test-suite/tests/cloudrun/internal/config"
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

// ReadingResult contains cold start measurements for one scheduled iteration.
type ReadingResult struct {
	RunID     string                           `json:"run_id"` // e.g., "2026-01-22"
	Iteration int                              `json:"iteration"`
	Timestamp time.Time                        `json:"timestamp"`
	Config    *config.Config                   `json:"config"` // For context in reports
	Services  map[string]*ColdStartMeasurement `json:"services"`
}

// ColdStartMeasurement contains a single cold start measurement for one service.
type ColdStartMeasurement struct {
	ServiceName      string        `json:"service_name"`
	ServiceURL       string        `json:"service_url"`
	TTFB             time.Duration `json:"ttfb"`
	ContainerStartup time.Duration `json:"container_startup,omitempty"`
	StatusCode       int           `json:"status_code"`
	Error            string        `json:"error,omitempty"`
}

// SaveReadingResult saves a reading result to GCS.
// Files are stored at: runs/<date>/reading-N.json
func (u *GCSUploader) SaveReadingResult(ctx context.Context, date string, iteration int, result *ReadingResult) (string, error) {
	// Build the GCS path: runs/<date>/reading-N.json
	gcsPath := path.Join("runs", date, fmt.Sprintf("reading-%d.json", iteration))

	// Marshal the result to JSON
	data, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		return "", fmt.Errorf("marshaling reading result: %w", err)
	}

	// Upload to GCS
	obj := u.client.Bucket(u.bucketName).Object(gcsPath)
	writer := obj.NewWriter(ctx)
	writer.ContentType = "application/json"

	if _, err := writer.Write(data); err != nil {
		writer.Close()
		return "", fmt.Errorf("writing to GCS: %w", err)
	}

	if err := writer.Close(); err != nil {
		return "", fmt.Errorf("finalizing upload: %w", err)
	}

	fullPath := fmt.Sprintf("gs://%s/%s", u.bucketName, gcsPath)
	return fullPath, nil
}

// LoadAllReadings loads all reading results for a given date from GCS.
// Returns readings sorted by iteration number.
func (u *GCSUploader) LoadAllReadings(ctx context.Context, date string) ([]*ReadingResult, error) {
	prefix := path.Join("runs", date) + "/"

	var readings []*ReadingResult

	it := u.client.Bucket(u.bucketName).Objects(ctx, &storage.Query{Prefix: prefix})
	for {
		attrs, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("listing objects: %w", err)
		}

		// Only process reading-*.json files
		if !strings.HasPrefix(filepath.Base(attrs.Name), "reading-") ||
			!strings.HasSuffix(attrs.Name, ".json") {
			continue
		}

		// Download and parse the reading
		reading, err := u.loadReading(ctx, attrs.Name)
		if err != nil {
			return nil, fmt.Errorf("loading reading %s: %w", attrs.Name, err)
		}

		readings = append(readings, reading)
	}

	// Sort by iteration number
	for i := 0; i < len(readings)-1; i++ {
		for j := i + 1; j < len(readings); j++ {
			if readings[i].Iteration > readings[j].Iteration {
				readings[i], readings[j] = readings[j], readings[i]
			}
		}
	}

	return readings, nil
}

// loadReading downloads and parses a single reading file from GCS.
func (u *GCSUploader) loadReading(ctx context.Context, gcsPath string) (*ReadingResult, error) {
	obj := u.client.Bucket(u.bucketName).Object(gcsPath)
	reader, err := obj.NewReader(ctx)
	if err != nil {
		return nil, fmt.Errorf("opening object: %w", err)
	}
	defer reader.Close()

	data, err := io.ReadAll(reader)
	if err != nil {
		return nil, fmt.Errorf("reading object: %w", err)
	}

	var reading ReadingResult
	if err := json.Unmarshal(data, &reading); err != nil {
		return nil, fmt.Errorf("parsing JSON: %w", err)
	}

	return &reading, nil
}

// CleanupRun deletes all files in the runs/<date>/ directory.
func (u *GCSUploader) CleanupRun(ctx context.Context, date string) error {
	prefix := path.Join("runs", date) + "/"

	it := u.client.Bucket(u.bucketName).Objects(ctx, &storage.Query{Prefix: prefix})
	for {
		attrs, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return fmt.Errorf("listing objects: %w", err)
		}

		if err := u.client.Bucket(u.bucketName).Object(attrs.Name).Delete(ctx); err != nil {
			return fmt.Errorf("deleting %s: %w", attrs.Name, err)
		}
	}

	return nil
}

// UploadAdhocResults uploads local results directory to gs://bucket/adhoc/<timestamp>/.
func (u *GCSUploader) UploadAdhocResults(ctx context.Context, timestamp time.Time, localDir string) ([]string, error) {
	// Build the GCS path prefix: adhoc/<timestamp>/
	tsStr := timestamp.UTC().Format("2006-01-22T15-04-05Z")
	prefix := path.Join("adhoc", tsStr)

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

// UploadBytes uploads raw bytes to a GCS path.
func (u *GCSUploader) UploadBytes(ctx context.Context, gcsPath string, data []byte, contentType string) (string, error) {
	obj := u.client.Bucket(u.bucketName).Object(gcsPath)
	writer := obj.NewWriter(ctx)
	writer.ContentType = contentType

	if _, err := writer.Write(data); err != nil {
		writer.Close()
		return "", fmt.Errorf("writing to GCS: %w", err)
	}

	if err := writer.Close(); err != nil {
		return "", fmt.Errorf("finalizing upload: %w", err)
	}

	return fmt.Sprintf("gs://%s/%s", u.bucketName, gcsPath), nil
}

// Discord webhook service implementation using Go and Gin.
//
// This service handles Discord interactions webhooks:
// - Validates Ed25519 signatures on incoming requests
// - Responds to Ping (type=1) with Pong (type=1)
// - Responds to Slash commands (type=2) with Deferred (type=5)
// - Publishes sanitized slash command payloads to Pub/Sub
package main

import (
	"context"
	"crypto/ed25519"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"cloud.google.com/go/pubsub/v2"
	pubsubpb "cloud.google.com/go/pubsub/v2/apiv1/pubsubpb"
	"github.com/gin-gonic/gin"
)

// Interaction types
const (
	InteractionTypePing               = 1
	InteractionTypeApplicationCommand = 2
)

// Response types
const (
	ResponseTypePong                   = 1
	ResponseTypeDeferredChannelMessage = 5
)

// Interaction represents a Discord interaction request
type Interaction struct {
	Type          int                    `json:"type"`
	ID            string                 `json:"id,omitempty"`
	ApplicationID string                 `json:"application_id,omitempty"`
	Token         string                 `json:"token,omitempty"`
	Data          map[string]interface{} `json:"data,omitempty"`
	GuildID       string                 `json:"guild_id,omitempty"`
	ChannelID     string                 `json:"channel_id,omitempty"`
	Member        map[string]interface{} `json:"member,omitempty"`
	User          map[string]interface{} `json:"user,omitempty"`
	Locale        string                 `json:"locale,omitempty"`
	GuildLocale   string                 `json:"guild_locale,omitempty"`
}

// InteractionResponse represents a Discord interaction response
type InteractionResponse struct {
	Type int                    `json:"type"`
	Data map[string]interface{} `json:"data,omitempty"`
}

var (
	publicKey       ed25519.PublicKey
	pubsubClient    *pubsub.Client
	pubsubPublisher *pubsub.Publisher
	projectID       string
)

func main() {
	// Load configuration from environment
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	publicKeyHex := os.Getenv("DISCORD_PUBLIC_KEY")
	if publicKeyHex == "" {
		log.Fatal("DISCORD_PUBLIC_KEY environment variable is required")
	}

	var err error
	publicKey, err = hex.DecodeString(publicKeyHex)
	if err != nil {
		log.Fatalf("Invalid DISCORD_PUBLIC_KEY: %v", err)
	}

	// Initialize Pub/Sub client
	projectID = os.Getenv("GOOGLE_CLOUD_PROJECT")
	topicName := os.Getenv("PUBSUB_TOPIC")

	if projectID != "" && topicName != "" {
		ctx := context.Background()
		pubsubClient, err = pubsub.NewClient(ctx, projectID)
		if err != nil {
			log.Printf("Warning: Failed to create Pub/Sub client: %v", err)
		} else {
			topicPath := fmt.Sprintf("projects/%s/topics/%s", projectID, topicName)

			// Ensure topic exists (for emulator, create if not exists)
			_, err := pubsubClient.TopicAdminClient.GetTopic(ctx, &pubsubpb.GetTopicRequest{
				Topic: topicPath,
			})
			if err != nil {
				// Topic doesn't exist, create it
				_, err = pubsubClient.TopicAdminClient.CreateTopic(ctx, &pubsubpb.Topic{
					Name: topicPath,
				})
				if err != nil {
					log.Printf("Warning: Failed to create topic: %v", err)
				}
			}

			// Create publisher for the topic
			pubsubPublisher = pubsubClient.Publisher(topicPath)
		}
	}

	// Set up Gin router
	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.Use(gin.Recovery())

	// Health check endpoint
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	// Discord interactions endpoint
	r.POST("/", handleInteraction)
	r.POST("/interactions", handleInteraction)

	// Start server
	log.Printf("Starting server on port %s", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

func handleInteraction(c *gin.Context) {
	// Read body
	body, err := io.ReadAll(c.Request.Body)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "failed to read body"})
		return
	}

	// Validate signature
	if !validateSignature(c.Request, body) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid signature"})
		return
	}

	// Parse interaction
	var interaction Interaction
	if err := json.Unmarshal(body, &interaction); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid JSON"})
		return
	}

	// Handle by type
	switch interaction.Type {
	case InteractionTypePing:
		handlePing(c)
	case InteractionTypeApplicationCommand:
		handleApplicationCommand(c, &interaction)
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "unsupported interaction type"})
	}
}

func validateSignature(r *http.Request, body []byte) bool {
	signature := r.Header.Get("X-Signature-Ed25519")
	timestamp := r.Header.Get("X-Signature-Timestamp")

	if signature == "" || timestamp == "" {
		return false
	}

	// Decode signature
	sigBytes, err := hex.DecodeString(signature)
	if err != nil {
		return false
	}

	// Check timestamp (must be within 5 seconds)
	ts, err := strconv.ParseInt(timestamp, 10, 64)
	if err != nil {
		return false
	}
	if time.Now().Unix()-ts > 5 {
		return false
	}

	// Verify signature: sign(timestamp + body)
	message := append([]byte(timestamp), body...)
	return ed25519.Verify(publicKey, message, sigBytes)
}

func handlePing(c *gin.Context) {
	// Respond with Pong - do NOT publish to Pub/Sub
	c.JSON(http.StatusOK, InteractionResponse{Type: ResponseTypePong})
}

func handleApplicationCommand(c *gin.Context, interaction *Interaction) {
	// Publish to Pub/Sub (if configured)
	if pubsubPublisher != nil {
		go publishToPubSub(interaction)
	}

	// Respond with deferred response (non-ephemeral)
	c.JSON(http.StatusOK, InteractionResponse{Type: ResponseTypeDeferredChannelMessage})
}

func publishToPubSub(interaction *Interaction) {
	// Create sanitized copy (remove sensitive fields)
	sanitized := &Interaction{
		Type:          interaction.Type,
		ID:            interaction.ID,
		ApplicationID: interaction.ApplicationID,
		// Token is intentionally NOT copied - sensitive data
		Data:        interaction.Data,
		GuildID:     interaction.GuildID,
		ChannelID:   interaction.ChannelID,
		Member:      interaction.Member,
		User:        interaction.User,
		Locale:      interaction.Locale,
		GuildLocale: interaction.GuildLocale,
	}

	data, err := json.Marshal(sanitized)
	if err != nil {
		log.Printf("Failed to marshal interaction for Pub/Sub: %v", err)
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Build attributes
	attributes := map[string]string{
		"interaction_id":   interaction.ID,
		"interaction_type": strconv.Itoa(interaction.Type),
		"application_id":   interaction.ApplicationID,
		"guild_id":         interaction.GuildID,
		"channel_id":       interaction.ChannelID,
		"timestamp":        time.Now().UTC().Format(time.RFC3339),
	}

	// Add command name if available
	if interaction.Data != nil {
		if name, ok := interaction.Data["name"].(string); ok {
			attributes["command_name"] = name
		}
	}

	// Build message
	msg := &pubsub.Message{
		Data:       data,
		Attributes: attributes,
	}

	result := pubsubPublisher.Publish(ctx, msg)
	if _, err := result.Get(ctx); err != nil {
		log.Printf("Failed to publish to Pub/Sub: %v", err)
	}
}

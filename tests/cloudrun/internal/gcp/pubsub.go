package gcp

import (
	"context"
	"fmt"
	"strings"
	"time"

	"cloud.google.com/go/pubsub"
)

// PubSubClient provides methods for managing Pub/Sub topics and subscriptions.
type PubSubClient struct {
	client    *pubsub.Client
	projectID string
}

// NewPubSubClient creates a new Pub/Sub client.
func NewPubSubClient(ctx context.Context, projectID string) (*PubSubClient, error) {
	client, err := pubsub.NewClient(ctx, projectID)
	if err != nil {
		return nil, fmt.Errorf("creating Pub/Sub client: %w", err)
	}

	return &PubSubClient{
		client:    client,
		projectID: projectID,
	}, nil
}

// Close closes the Pub/Sub client.
func (c *PubSubClient) Close() error {
	return c.client.Close()
}

// PubSubConfig contains configuration for Pub/Sub resources.
type PubSubConfig struct {
	RunID string // Unique run identifier
}

// TopicName returns the topic name: discord-benchmark-{RunID}
func (cfg *PubSubConfig) TopicName() string {
	return fmt.Sprintf("discord-benchmark-%s", cfg.RunID)
}

// SubscriptionName returns the subscription name: discord-benchmark-{RunID}-sub
func (cfg *PubSubConfig) SubscriptionName() string {
	return fmt.Sprintf("discord-benchmark-%s-sub", cfg.RunID)
}

// CreateTopic creates a Pub/Sub topic for the benchmark run.
func (c *PubSubClient) CreateTopic(ctx context.Context, cfg PubSubConfig) error {
	topicName := cfg.TopicName()
	topic := c.client.Topic(topicName)

	exists, err := topic.Exists(ctx)
	if err != nil {
		return fmt.Errorf("checking topic existence: %w", err)
	}

	if exists {
		return nil // Topic already exists
	}

	_, err = c.client.CreateTopic(ctx, topicName)
	if err != nil {
		return fmt.Errorf("creating topic %s: %w", topicName, err)
	}

	return nil
}

// CreateSubscription creates a Pub/Sub subscription for the benchmark run.
func (c *PubSubClient) CreateSubscription(ctx context.Context, cfg PubSubConfig) error {
	topicName := cfg.TopicName()
	subName := cfg.SubscriptionName()

	topic := c.client.Topic(topicName)
	sub := c.client.Subscription(subName)

	exists, err := sub.Exists(ctx)
	if err != nil {
		return fmt.Errorf("checking subscription existence: %w", err)
	}

	if exists {
		return nil // Subscription already exists
	}

	_, err = c.client.CreateSubscription(ctx, subName, pubsub.SubscriptionConfig{
		Topic:       topic,
		AckDeadline: 10 * time.Second,
	})
	if err != nil {
		return fmt.Errorf("creating subscription %s: %w", subName, err)
	}

	return nil
}

// Message represents a Pub/Sub message.
type Message struct {
	ID         string
	Data       []byte
	Attributes map[string]string
	PublishTime time.Time
}

// PullMessages pulls messages from the subscription with a timeout.
func (c *PubSubClient) PullMessages(ctx context.Context, cfg PubSubConfig, timeout time.Duration) ([]Message, error) {
	subName := cfg.SubscriptionName()
	sub := c.client.Subscription(subName)

	// Configure for pulling a batch of messages
	sub.ReceiveSettings.MaxOutstandingMessages = 100
	sub.ReceiveSettings.MaxOutstandingBytes = 10 * 1024 * 1024

	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	var messages []Message
	err := sub.Receive(ctx, func(ctx context.Context, msg *pubsub.Message) {
		messages = append(messages, Message{
			ID:          msg.ID,
			Data:        msg.Data,
			Attributes:  msg.Attributes,
			PublishTime: msg.PublishTime,
		})
		msg.Ack()
	})

	// Context deadline exceeded is expected when using timeout
	if err != nil && ctx.Err() != context.DeadlineExceeded {
		return nil, fmt.Errorf("receiving messages: %w", err)
	}

	return messages, nil
}

// DeleteTopic deletes the Pub/Sub topic for the benchmark run.
func (c *PubSubClient) DeleteTopic(ctx context.Context, cfg PubSubConfig) error {
	topicName := cfg.TopicName()
	topic := c.client.Topic(topicName)

	exists, err := topic.Exists(ctx)
	if err != nil {
		return fmt.Errorf("checking topic existence: %w", err)
	}

	if !exists {
		return nil // Topic doesn't exist, nothing to delete
	}

	if err := topic.Delete(ctx); err != nil {
		return fmt.Errorf("deleting topic %s: %w", topicName, err)
	}

	return nil
}

// DeleteSubscription deletes the Pub/Sub subscription for the benchmark run.
func (c *PubSubClient) DeleteSubscription(ctx context.Context, cfg PubSubConfig) error {
	subName := cfg.SubscriptionName()
	sub := c.client.Subscription(subName)

	exists, err := sub.Exists(ctx)
	if err != nil {
		return fmt.Errorf("checking subscription existence: %w", err)
	}

	if !exists {
		return nil // Subscription doesn't exist, nothing to delete
	}

	if err := sub.Delete(ctx); err != nil {
		return fmt.Errorf("deleting subscription %s: %w", subName, err)
	}

	return nil
}

// DeleteByRunID deletes all Pub/Sub resources for a specific run ID.
func (c *PubSubClient) DeleteByRunID(ctx context.Context, runID string) error {
	cfg := PubSubConfig{RunID: runID}

	// Delete subscription first (depends on topic)
	if err := c.DeleteSubscription(ctx, cfg); err != nil {
		return err
	}

	// Delete topic
	if err := c.DeleteTopic(ctx, cfg); err != nil {
		return err
	}

	return nil
}

// ListByPrefix returns all topics and subscriptions matching the given prefix.
func (c *PubSubClient) ListByPrefix(ctx context.Context, prefix string) (topics []string, subs []string, err error) {
	// List topics
	topicIter := c.client.Topics(ctx)
	for {
		topic, err := topicIter.Next()
		if err != nil {
			break
		}
		if strings.HasPrefix(topic.ID(), prefix) {
			topics = append(topics, topic.ID())
		}
	}

	// List subscriptions
	subIter := c.client.Subscriptions(ctx)
	for {
		sub, err := subIter.Next()
		if err != nil {
			break
		}
		if strings.HasPrefix(sub.ID(), prefix) {
			subs = append(subs, sub.ID())
		}
	}

	return topics, subs, nil
}

// Setup creates both topic and subscription for a benchmark run.
func (c *PubSubClient) Setup(ctx context.Context, cfg PubSubConfig) error {
	if err := c.CreateTopic(ctx, cfg); err != nil {
		return err
	}
	if err := c.CreateSubscription(ctx, cfg); err != nil {
		return err
	}
	return nil
}

// Cleanup deletes both subscription and topic for a benchmark run.
func (c *PubSubClient) Cleanup(ctx context.Context, cfg PubSubConfig) error {
	// Delete subscription first
	if err := c.DeleteSubscription(ctx, cfg); err != nil {
		return err
	}
	// Then delete topic
	if err := c.DeleteTopic(ctx, cfg); err != nil {
		return err
	}
	return nil
}

// GetTopicPath returns the full topic path for use in environment variables.
func (c *PubSubClient) GetTopicPath(cfg PubSubConfig) string {
	return fmt.Sprintf("projects/%s/topics/%s", c.projectID, cfg.TopicName())
}

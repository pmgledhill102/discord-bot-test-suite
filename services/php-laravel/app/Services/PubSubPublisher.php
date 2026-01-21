<?php

namespace App\Services;

use Google\Cloud\PubSub\PubSubClient;
use Illuminate\Support\Facades\Log;

class PubSubPublisher
{
    private ?PubSubClient $client = null;

    private ?string $topicName = null;

    public function __construct()
    {
        $projectId = env('GOOGLE_CLOUD_PROJECT');
        $this->topicName = env('PUBSUB_TOPIC');

        if ($projectId && $this->topicName) {
            try {
                $this->client = new PubSubClient([
                    'projectId' => $projectId,
                ]);

                // Ensure topic exists (for emulator)
                $topic = $this->client->topic($this->topicName);
                if (! $topic->exists()) {
                    $this->client->createTopic($this->topicName);
                }
            } catch (\Exception $e) {
                Log::warning('Failed to initialize Pub/Sub client: '.$e->getMessage());
                $this->client = null;
            }
        }
    }

    public function publish(array $interaction): void
    {
        if (! $this->client || ! $this->topicName) {
            return;
        }

        // Create sanitized copy (remove sensitive fields)
        $sanitized = [
            'type' => $interaction['type'] ?? null,
            'id' => $interaction['id'] ?? null,
            'application_id' => $interaction['application_id'] ?? null,
            // Token is intentionally NOT copied - sensitive data
            'data' => $interaction['data'] ?? null,
            'guild_id' => $interaction['guild_id'] ?? null,
            'channel_id' => $interaction['channel_id'] ?? null,
            'member' => $interaction['member'] ?? null,
            'user' => $interaction['user'] ?? null,
            'locale' => $interaction['locale'] ?? null,
            'guild_locale' => $interaction['guild_locale'] ?? null,
        ];

        // Remove null values
        $sanitized = array_filter($sanitized, fn ($v) => $v !== null);

        $data = json_encode($sanitized);

        // Build attributes
        $attributes = [
            'interaction_id' => $interaction['id'] ?? '',
            'interaction_type' => (string) ($interaction['type'] ?? ''),
            'application_id' => $interaction['application_id'] ?? '',
            'guild_id' => $interaction['guild_id'] ?? '',
            'channel_id' => $interaction['channel_id'] ?? '',
            'timestamp' => gmdate('Y-m-d\TH:i:s\Z'),
        ];

        // Add command name if available
        if (isset($interaction['data']['name'])) {
            $attributes['command_name'] = $interaction['data']['name'];
        }

        try {
            $topic = $this->client->topic($this->topicName);
            $topic->publish([
                'data' => $data,
                'attributes' => $attributes,
            ]);
        } catch (\Exception $e) {
            Log::error('Failed to publish to Pub/Sub: '.$e->getMessage());
        }
    }
}

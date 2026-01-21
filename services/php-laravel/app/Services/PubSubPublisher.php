<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Pub/Sub publisher using direct HTTP REST API calls to the emulator.
 *
 * This bypasses the Google Cloud PHP library for better emulator compatibility.
 */
class PubSubPublisher
{
    private ?string $projectId = null;

    private ?string $topicName = null;

    private ?string $emulatorHost = null;

    public function __construct()
    {
        // Use getenv() directly for Docker environment variables
        $this->projectId = getenv('GOOGLE_CLOUD_PROJECT') ?: env('GOOGLE_CLOUD_PROJECT');
        $this->topicName = getenv('PUBSUB_TOPIC') ?: env('PUBSUB_TOPIC');
        $this->emulatorHost = getenv('PUBSUB_EMULATOR_HOST') ?: env('PUBSUB_EMULATOR_HOST');

        if ($this->isConfigured()) {
            Log::info("Pub/Sub configured: emulator={$this->emulatorHost} project={$this->projectId} topic={$this->topicName}");
        }
    }

    public function isConfigured(): bool
    {
        return ! empty($this->projectId) && ! empty($this->topicName) && ! empty($this->emulatorHost);
    }

    public function publish(array $interaction): void
    {
        if (! $this->isConfigured()) {
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
            // Build Pub/Sub REST API URL
            $url = "http://{$this->emulatorHost}/v1/projects/{$this->projectId}/topics/{$this->topicName}:publish";

            // Build request body
            $requestBody = [
                'messages' => [
                    [
                        'data' => base64_encode($data),
                        'attributes' => $attributes,
                    ],
                ],
            ];

            // Send POST request to Pub/Sub emulator
            $response = Http::timeout(5)
                ->withHeaders(['Content-Type' => 'application/json'])
                ->post($url, $requestBody);

            if ($response->successful()) {
                Log::debug('Published to Pub/Sub successfully');
            } else {
                Log::error("Pub/Sub publish failed: HTTP {$response->status()} - {$response->body()}");
            }
        } catch (\Exception $e) {
            Log::error('Failed to publish to Pub/Sub: '.$e->getMessage());
        }
    }
}

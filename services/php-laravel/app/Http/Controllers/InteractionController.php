<?php

namespace App\Http\Controllers;

use App\Services\PubSubPublisher;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class InteractionController
{
    // Interaction types
    private const INTERACTION_TYPE_PING = 1;

    private const INTERACTION_TYPE_APPLICATION_COMMAND = 2;

    // Response types
    private const RESPONSE_TYPE_PONG = 1;

    private const RESPONSE_TYPE_DEFERRED_CHANNEL_MESSAGE = 5;

    private PubSubPublisher $pubsub;

    public function __construct(PubSubPublisher $pubsub)
    {
        $this->pubsub = $pubsub;
    }

    public function handle(Request $request): JsonResponse
    {
        $interaction = $request->json()->all();

        // Ensure interaction is valid
        if (empty($interaction) || ! is_array($interaction)) {
            return response()->json(['error' => 'invalid JSON'], 400);
        }

        $type = $interaction['type'] ?? null;

        // Check if type exists
        if ($type === null) {
            return response()->json(['error' => 'unsupported interaction type'], 400);
        }

        // Check if type is an integer
        if (! is_int($type)) {
            return response()->json(['error' => 'unsupported interaction type'], 400);
        }

        return match ($type) {
            self::INTERACTION_TYPE_PING => $this->handlePing(),
            self::INTERACTION_TYPE_APPLICATION_COMMAND => $this->handleApplicationCommand($interaction),
            default => response()->json(['error' => 'unsupported interaction type'], 400),
        };
    }

    private function handlePing(): JsonResponse
    {
        // Respond with Pong - do NOT publish to Pub/Sub
        return response()->json(['type' => self::RESPONSE_TYPE_PONG]);
    }

    private function handleApplicationCommand(array $interaction): JsonResponse
    {
        // Publish to Pub/Sub asynchronously (in PHP we do it inline but quickly)
        $this->pubsub->publish($interaction);

        // Respond with deferred response (non-ephemeral)
        return response()->json(['type' => self::RESPONSE_TYPE_DEFERRED_CHANNEL_MESSAGE]);
    }
}

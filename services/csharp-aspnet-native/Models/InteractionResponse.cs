// Discord interaction response models.

using System.Text.Json.Serialization;

namespace DiscordWebhookNative.Models;

public class InteractionResponse
{
    [JsonPropertyName("type")]
    public int Type { get; set; }

    /// <summary>
    /// Creates a Pong response (type 1) for Ping interactions.
    /// </summary>
    public static InteractionResponse Pong() => new() { Type = 1 };

    /// <summary>
    /// Creates a Deferred response (type 5) for slash command interactions.
    /// </summary>
    public static InteractionResponse Deferred() => new() { Type = 5 };
}

public class ErrorResponse
{
    [JsonPropertyName("error")]
    public string Error { get; set; } = string.Empty;

    public ErrorResponse(string error)
    {
        Error = error;
    }
}

public class HealthResponse
{
    [JsonPropertyName("status")]
    public string Status { get; set; } = "ok";
}

// Pub/Sub REST API models
public class PubSubRequest
{
    [JsonPropertyName("messages")]
    public List<PubSubMessage> Messages { get; set; } = new();
}

public class PubSubMessage
{
    [JsonPropertyName("data")]
    public string Data { get; set; } = string.Empty;

    [JsonPropertyName("attributes")]
    public Dictionary<string, string> Attributes { get; set; } = new();
}

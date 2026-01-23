// JSON source generator context for AOT-compatible serialization.
// System.Text.Json uses reflection by default, which breaks with Native AOT.
// Source generators create compile-time serialization code instead.

using System.Text.Json.Serialization;

namespace DiscordWebhookNative.Models;

[JsonSourceGenerationOptions(
    PropertyNamingPolicy = JsonKnownNamingPolicy.SnakeCaseLower,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull)]
[JsonSerializable(typeof(Interaction))]
[JsonSerializable(typeof(InteractionResponse))]
[JsonSerializable(typeof(ErrorResponse))]
[JsonSerializable(typeof(HealthResponse))]
[JsonSerializable(typeof(PubSubRequest))]
[JsonSerializable(typeof(PubSubMessage))]
public partial class AppJsonContext : JsonSerializerContext
{
}

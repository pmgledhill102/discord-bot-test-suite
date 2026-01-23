// Discord interaction request model.
// Strongly typed for AOT compatibility (no dynamic JsonNode access).

using System.Text.Json.Serialization;

namespace DiscordWebhookNative.Models;

public class Interaction
{
    [JsonPropertyName("type")]
    public int Type { get; set; }

    [JsonPropertyName("id")]
    public string? Id { get; set; }

    [JsonPropertyName("application_id")]
    public string? ApplicationId { get; set; }

    [JsonPropertyName("token")]
    public string? Token { get; set; }

    [JsonPropertyName("guild_id")]
    public string? GuildId { get; set; }

    [JsonPropertyName("channel_id")]
    public string? ChannelId { get; set; }

    [JsonPropertyName("data")]
    public InteractionData? Data { get; set; }

    [JsonPropertyName("member")]
    public object? Member { get; set; }

    [JsonPropertyName("user")]
    public object? User { get; set; }

    [JsonPropertyName("locale")]
    public string? Locale { get; set; }

    [JsonPropertyName("guild_locale")]
    public string? GuildLocale { get; set; }

    /// <summary>
    /// Creates a sanitized copy of the interaction without the token field.
    /// </summary>
    public Interaction CreateSanitizedCopy()
    {
        return new Interaction
        {
            Type = Type,
            Id = Id,
            ApplicationId = ApplicationId,
            Token = null, // Explicitly exclude token
            GuildId = GuildId,
            ChannelId = ChannelId,
            Data = Data,
            Member = Member,
            User = User,
            Locale = Locale,
            GuildLocale = GuildLocale
        };
    }
}

public class InteractionData
{
    [JsonPropertyName("id")]
    public string? Id { get; set; }

    [JsonPropertyName("name")]
    public string? Name { get; set; }

    [JsonPropertyName("type")]
    public int? Type { get; set; }

    [JsonPropertyName("options")]
    public object? Options { get; set; }
}

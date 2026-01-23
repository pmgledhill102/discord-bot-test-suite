// Pub/Sub service using REST API instead of gRPC.
// gRPC is reflection-heavy and breaks with Native AOT.
// This follows the pattern from java-quarkus-native.

using System.Text;
using System.Text.Json;
using DiscordWebhookNative.Models;

namespace DiscordWebhookNative.Services;

public class PubSubService
{
    private readonly HttpClient _httpClient;
    private readonly string? _publishUrl;
    private readonly bool _configured;
    private readonly ILogger _logger;

    public PubSubService(ILogger logger)
    {
        _logger = logger;
        _httpClient = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(10)
        };

        var projectId = Environment.GetEnvironmentVariable("GOOGLE_CLOUD_PROJECT");
        var topicName = Environment.GetEnvironmentVariable("PUBSUB_TOPIC");
        var emulatorHost = Environment.GetEnvironmentVariable("PUBSUB_EMULATOR_HOST");

        if (string.IsNullOrEmpty(projectId) || string.IsNullOrEmpty(topicName))
        {
            _logger.LogInformation("Pub/Sub not configured (missing project or topic)");
            _configured = false;
            return;
        }

        if (string.IsNullOrEmpty(emulatorHost))
        {
            _logger.LogInformation("Pub/Sub emulator host not configured");
            _configured = false;
            return;
        }

        // Build the REST API URL for publishing
        // Format: http://{emulator}/v1/projects/{project}/topics/{topic}:publish
        var host = emulatorHost;
        if (!host.StartsWith("http://") && !host.StartsWith("https://"))
        {
            host = "http://" + host;
        }
        _publishUrl = $"{host}/v1/projects/{projectId}/topics/{topicName}:publish";

        _configured = true;
        _logger.LogInformation("Pub/Sub HTTP client configured for: {PublishUrl}", _publishUrl);
    }

    public bool IsConfigured => _configured;

    /// <summary>
    /// Publishes an interaction asynchronously (fire-and-forget).
    /// </summary>
    public void PublishAsync(Interaction interaction)
    {
        if (!_configured)
        {
            return;
        }

        _ = Task.Run(async () =>
        {
            try
            {
                await PublishInternalAsync(interaction);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to publish message");
            }
        });
    }

    private async Task PublishInternalAsync(Interaction interaction)
    {
        // Create sanitized copy (remove token)
        var sanitized = interaction.CreateSanitizedCopy();
        var json = JsonSerializer.Serialize(sanitized, AppJsonContext.Default.Interaction);

        // Build attributes
        var attributes = new Dictionary<string, string>
        {
            ["interaction_type"] = interaction.Type.ToString(),
            ["timestamp"] = DateTime.UtcNow.ToString("o")
        };

        if (!string.IsNullOrEmpty(interaction.Id))
        {
            attributes["interaction_id"] = interaction.Id;
        }
        if (!string.IsNullOrEmpty(interaction.ApplicationId))
        {
            attributes["application_id"] = interaction.ApplicationId;
        }
        if (!string.IsNullOrEmpty(interaction.GuildId))
        {
            attributes["guild_id"] = interaction.GuildId;
        }
        if (!string.IsNullOrEmpty(interaction.ChannelId))
        {
            attributes["channel_id"] = interaction.ChannelId;
        }
        if (!string.IsNullOrEmpty(interaction.Data?.Name))
        {
            attributes["command_name"] = interaction.Data.Name;
        }

        // Build Pub/Sub REST API request body
        var request = new PubSubRequest
        {
            Messages = new List<PubSubMessage>
            {
                new PubSubMessage
                {
                    Data = Convert.ToBase64String(Encoding.UTF8.GetBytes(json)),
                    Attributes = attributes
                }
            }
        };

        var requestJson = JsonSerializer.Serialize(request, AppJsonContext.Default.PubSubRequest);
        var content = new StringContent(requestJson, Encoding.UTF8, "application/json");

        var response = await _httpClient.PostAsync(_publishUrl, content);

        if (response.IsSuccessStatusCode)
        {
            _logger.LogDebug("Published message to Pub/Sub via HTTP");
        }
        else
        {
            var body = await response.Content.ReadAsStringAsync();
            _logger.LogError("Failed to publish to Pub/Sub: HTTP {StatusCode} - {Body}",
                (int)response.StatusCode, body);
        }
    }
}

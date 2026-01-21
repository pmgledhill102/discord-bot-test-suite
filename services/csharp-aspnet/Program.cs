// Discord webhook service implementation using C# and ASP.NET Core.
//
// This service handles Discord interactions webhooks:
// - Validates Ed25519 signatures on incoming requests
// - Responds to Ping (type=1) with Pong (type=1)
// - Responds to Slash commands (type=2) with Deferred (type=5)
// - Publishes sanitized slash command payloads to Pub/Sub

using System.Text.Json.Nodes;
using Google.Cloud.PubSub.V1;
using NSec.Cryptography;

var builder = WebApplication.CreateBuilder(args);
builder.Logging.ClearProviders();
builder.Logging.AddConsole();

var app = builder.Build();

// Configuration
var port = Environment.GetEnvironmentVariable("PORT") ?? "8080";
var publicKeyHex = Environment.GetEnvironmentVariable("DISCORD_PUBLIC_KEY")
    ?? throw new InvalidOperationException("DISCORD_PUBLIC_KEY environment variable is required");

var publicKeyBytes = Convert.FromHexString(publicKeyHex);
var publicKey = PublicKey.Import(SignatureAlgorithm.Ed25519, publicKeyBytes, KeyBlobFormat.RawPublicKey);

// Pub/Sub setup
var projectId = Environment.GetEnvironmentVariable("GOOGLE_CLOUD_PROJECT");
var topicName = Environment.GetEnvironmentVariable("PUBSUB_TOPIC");
var emulatorHost = Environment.GetEnvironmentVariable("PUBSUB_EMULATOR_HOST");
PublisherClient? publisher = null;

if (!string.IsNullOrEmpty(projectId) && !string.IsNullOrEmpty(topicName))
{
    try
    {
        var topicPath = TopicName.FromProjectTopic(projectId, topicName);

        // Configure for emulator if specified
        if (!string.IsNullOrEmpty(emulatorHost))
        {
            Console.WriteLine($"Pub/Sub configured for emulator: {emulatorHost}");

            // Create API client with emulator settings
            var apiClientBuilder = new PublisherServiceApiClientBuilder
            {
                Endpoint = emulatorHost,
                ChannelCredentials = Grpc.Core.ChannelCredentials.Insecure
            };
            var publisherApi = apiClientBuilder.Build();

            // Create topic if it doesn't exist (for emulator)
            try
            {
                publisherApi.GetTopic(topicPath);
            }
            catch (Grpc.Core.RpcException ex) when (ex.StatusCode == Grpc.Core.StatusCode.NotFound)
            {
                publisherApi.CreateTopic(topicPath);
                Console.WriteLine($"Created topic: {topicName}");
            }

            // Create publisher client with emulator settings
            var clientBuilder = new PublisherClientBuilder
            {
                TopicName = topicPath,
                ApiSettings = new PublisherServiceApiSettings(),
                Endpoint = emulatorHost,
                ChannelCredentials = Grpc.Core.ChannelCredentials.Insecure
            };
            publisher = clientBuilder.Build();
        }
        else
        {
            // Standard client for production
            var publisherApi = PublisherServiceApiClient.Create();
            try
            {
                publisherApi.GetTopic(topicPath);
            }
            catch (Grpc.Core.RpcException ex) when (ex.StatusCode == Grpc.Core.StatusCode.NotFound)
            {
                publisherApi.CreateTopic(topicPath);
            }
            publisher = PublisherClient.Create(topicPath);
        }

        Console.WriteLine($"Pub/Sub publisher initialized for topic: {topicName}");
    }
    catch (Exception ex)
    {
        Console.WriteLine($"Warning: Failed to initialize Pub/Sub: {ex.Message}");
        Console.WriteLine(ex.StackTrace);
    }
}

// Health check endpoint
app.MapGet("/health", () => Results.Json(new { status = "ok" }));

// Discord interactions endpoints
app.MapPost("/", (Delegate)HandleInteraction);
app.MapPost("/interactions", (Delegate)HandleInteraction);

app.Run($"http://0.0.0.0:{port}");

async Task<IResult> HandleInteraction(HttpContext context)
{
    // Read body
    using var reader = new StreamReader(context.Request.Body);
    var body = await reader.ReadToEndAsync();
    var bodyBytes = System.Text.Encoding.UTF8.GetBytes(body);

    // Validate signature
    if (!ValidateSignature(context.Request, bodyBytes))
    {
        return Results.Json(new { error = "invalid signature" }, statusCode: 401);
    }

    // Parse interaction
    JsonNode? json;
    try
    {
        json = JsonNode.Parse(body);
        if (json is not JsonObject)
        {
            return Results.Json(new { error = "invalid JSON" }, statusCode: 400);
        }
    }
    catch
    {
        return Results.Json(new { error = "invalid JSON" }, statusCode: 400);
    }

    // Get type - must be a valid integer
    int type;
    try
    {
        var typeNode = json["type"];
        if (typeNode == null)
        {
            return Results.Json(new { error = "invalid JSON" }, statusCode: 400);
        }
        type = typeNode.GetValue<int>();
    }
    catch
    {
        return Results.Json(new { error = "invalid JSON" }, statusCode: 400);
    }

    // Handle by type
    return type switch
    {
        1 => HandlePing(),
        2 => HandleApplicationCommand(json),
        _ => Results.Json(new { error = "unsupported interaction type" }, statusCode: 400)
    };
}

bool ValidateSignature(HttpRequest request, byte[] body)
{
    var signature = request.Headers["X-Signature-Ed25519"].FirstOrDefault();
    var timestamp = request.Headers["X-Signature-Timestamp"].FirstOrDefault();

    if (string.IsNullOrEmpty(signature) || string.IsNullOrEmpty(timestamp))
    {
        return false;
    }

    // Decode signature
    byte[] sigBytes;
    try
    {
        sigBytes = Convert.FromHexString(signature);
    }
    catch
    {
        return false;
    }

    if (sigBytes.Length != 64)
    {
        return false;
    }

    // Check timestamp (must be within 5 seconds)
    if (!long.TryParse(timestamp, out var ts))
    {
        return false;
    }

    var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
    if (now - ts > 5)
    {
        return false;
    }

    // Verify signature: sign(timestamp + body)
    var message = System.Text.Encoding.UTF8.GetBytes(timestamp).Concat(body).ToArray();

    try
    {
        return SignatureAlgorithm.Ed25519.Verify(publicKey, message, sigBytes);
    }
    catch
    {
        return false;
    }
}

IResult HandlePing()
{
    // Respond with Pong - do NOT publish to Pub/Sub
    return Results.Json(new { type = 1 });
}

IResult HandleApplicationCommand(JsonNode interaction)
{
    // Publish to Pub/Sub (if configured)
    if (publisher != null)
    {
        _ = PublishToPubSubAsync(interaction);
    }

    // Respond with deferred response (non-ephemeral)
    return Results.Json(new { type = 5 });
}

async Task PublishToPubSubAsync(JsonNode interaction)
{
    try
    {
        // Create sanitized copy (remove sensitive fields)
        var sanitized = new JsonObject();

        var safeFields = new[] { "type", "id", "application_id", "data", "guild_id", "channel_id", "member", "user", "locale", "guild_locale" };
        foreach (var field in safeFields)
        {
            if (interaction[field] != null)
            {
                sanitized[field] = JsonNode.Parse(interaction[field]!.ToJsonString());
            }
        }

        var data = sanitized.ToJsonString();

        // Build message with attributes
        var attributes = new Dictionary<string, string>
        {
            ["interaction_id"] = interaction["id"]?.GetValue<string>() ?? "",
            ["interaction_type"] = interaction["type"]?.GetValue<int>().ToString() ?? "",
            ["application_id"] = interaction["application_id"]?.GetValue<string>() ?? "",
            ["guild_id"] = interaction["guild_id"]?.GetValue<string>() ?? "",
            ["channel_id"] = interaction["channel_id"]?.GetValue<string>() ?? "",
            ["timestamp"] = DateTime.UtcNow.ToString("o")
        };

        // Add command name if available
        var commandName = interaction["data"]?["name"]?.GetValue<string>();
        if (!string.IsNullOrEmpty(commandName))
        {
            attributes["command_name"] = commandName;
        }

        var message = new PubsubMessage
        {
            Data = Google.Protobuf.ByteString.CopyFromUtf8(data),
            Attributes = { attributes }
        };

        await publisher!.PublishAsync(message);
    }
    catch (Exception ex)
    {
        Console.WriteLine($"Failed to publish to Pub/Sub: {ex.Message}");
    }
}

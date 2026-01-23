// Discord webhook service implementation using C# and ASP.NET Core with Native AOT.
//
// This service handles Discord interactions webhooks:
// - Validates Ed25519 signatures on incoming requests
// - Responds to Ping (type=1) with Pong (type=1)
// - Responds to Slash commands (type=2) with Deferred (type=5)
// - Publishes sanitized slash command payloads to Pub/Sub via REST API
//
// Native AOT considerations:
// - Uses WebApplication.CreateSlimBuilder() for AOT-compatible minimal API
// - Uses System.Text.Json source generators (no reflection)
// - Uses REST API for Pub/Sub instead of gRPC (gRPC breaks AOT)

using System.Text.Json;
using DiscordWebhookNative.Models;
using DiscordWebhookNative.Services;

var builder = WebApplication.CreateSlimBuilder(args);

// Configure JSON serialization with source generator
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.TypeInfoResolverChain.Insert(0, AppJsonContext.Default);
});

builder.Logging.ClearProviders();
builder.Logging.AddConsole();

var app = builder.Build();

// Configuration
var port = Environment.GetEnvironmentVariable("PORT") ?? "8080";
var publicKeyHex = Environment.GetEnvironmentVariable("DISCORD_PUBLIC_KEY")
    ?? throw new InvalidOperationException("DISCORD_PUBLIC_KEY environment variable is required");

// Initialize services
var signatureService = new SignatureService(publicKeyHex);
var pubSubService = new PubSubService(app.Logger);

// Health check endpoint
app.MapGet("/health", () => Results.Json(new HealthResponse(), AppJsonContext.Default.HealthResponse));

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
    var signature = context.Request.Headers["X-Signature-Ed25519"].FirstOrDefault();
    var timestamp = context.Request.Headers["X-Signature-Timestamp"].FirstOrDefault();

    if (!signatureService.ValidateSignature(signature, timestamp, bodyBytes))
    {
        return Results.Json(
            new ErrorResponse("invalid signature"),
            AppJsonContext.Default.ErrorResponse,
            statusCode: 401);
    }

    // Parse interaction
    Interaction? interaction;
    try
    {
        interaction = JsonSerializer.Deserialize(body, AppJsonContext.Default.Interaction);
        if (interaction == null)
        {
            return Results.Json(
                new ErrorResponse("invalid JSON"),
                AppJsonContext.Default.ErrorResponse,
                statusCode: 400);
        }
    }
    catch
    {
        return Results.Json(
            new ErrorResponse("invalid JSON"),
            AppJsonContext.Default.ErrorResponse,
            statusCode: 400);
    }

    // Handle by type
    return interaction.Type switch
    {
        1 => HandlePing(),
        2 => HandleApplicationCommand(interaction),
        _ => Results.Json(
            new ErrorResponse("unsupported interaction type"),
            AppJsonContext.Default.ErrorResponse,
            statusCode: 400)
    };
}

IResult HandlePing()
{
    // Respond with Pong - do NOT publish to Pub/Sub
    return Results.Json(InteractionResponse.Pong(), AppJsonContext.Default.InteractionResponse);
}

IResult HandleApplicationCommand(Interaction interaction)
{
    // Publish to Pub/Sub (if configured)
    if (pubSubService.IsConfigured)
    {
        pubSubService.PublishAsync(interaction);
    }

    // Respond with deferred response (non-ephemeral)
    return Results.Json(InteractionResponse.Deferred(), AppJsonContext.Default.InteractionResponse);
}

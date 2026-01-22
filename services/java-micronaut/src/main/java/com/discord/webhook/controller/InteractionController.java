package com.discord.webhook.controller;

import com.discord.webhook.model.ErrorResponse;
import com.discord.webhook.model.HealthResponse;
import com.discord.webhook.model.Interaction;
import com.discord.webhook.model.InteractionResponse;
import com.discord.webhook.service.PubSubService;
import com.discord.webhook.service.SignatureService;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.micronaut.core.annotation.Nullable;
import io.micronaut.http.HttpResponse;
import io.micronaut.http.MediaType;
import io.micronaut.http.annotation.*;
import jakarta.inject.Inject;

import java.io.IOException;

@Controller
public class InteractionController {

    private static final String HEADER_SIGNATURE = "X-Signature-Ed25519";
    private static final String HEADER_TIMESTAMP = "X-Signature-Timestamp";

    @Inject
    private SignatureService signatureService;

    @Inject
    private PubSubService pubSubService;

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Get("/health")
    @Produces(MediaType.APPLICATION_JSON)
    public HttpResponse<HealthResponse> health() {
        return HttpResponse.ok(new HealthResponse("ok"));
    }

    @Post("/")
    @Consumes(MediaType.APPLICATION_JSON)
    @Produces(MediaType.APPLICATION_JSON)
    public HttpResponse<?> handleInteraction(
            @Nullable @Header(HEADER_SIGNATURE) String signature,
            @Nullable @Header(HEADER_TIMESTAMP) String timestamp,
            @Body byte[] body) {
        return processInteraction(signature, timestamp, body);
    }

    @Post("/interactions")
    @Consumes(MediaType.APPLICATION_JSON)
    @Produces(MediaType.APPLICATION_JSON)
    public HttpResponse<?> handleInteractionAlt(
            @Nullable @Header(HEADER_SIGNATURE) String signature,
            @Nullable @Header(HEADER_TIMESTAMP) String timestamp,
            @Body byte[] body) {
        return processInteraction(signature, timestamp, body);
    }

    private HttpResponse<?> processInteraction(String signature, String timestamp, byte[] body) {
        // Check for missing signature headers - must return 401 per Discord spec
        if (signature == null || signature.isEmpty()) {
            return HttpResponse.unauthorized().body(new ErrorResponse("missing signature"));
        }
        if (timestamp == null || timestamp.isEmpty()) {
            return HttpResponse.unauthorized().body(new ErrorResponse("missing timestamp"));
        }

        // Validate signature
        if (!signatureService.validateSignature(signature, timestamp, body)) {
            return HttpResponse.unauthorized().body(new ErrorResponse("invalid signature"));
        }

        // Parse interaction
        Interaction interaction;
        try {
            interaction = objectMapper.readValue(body, Interaction.class);
        } catch (IOException e) {
            return HttpResponse.badRequest(new ErrorResponse("invalid JSON"));
        }

        // Check for null body (JSON "null")
        if (interaction == null) {
            return HttpResponse.badRequest(new ErrorResponse("invalid JSON"));
        }

        // Handle by type
        return switch (interaction.getType()) {
            case Interaction.TYPE_PING -> handlePing();
            case Interaction.TYPE_APPLICATION_COMMAND -> handleApplicationCommand(interaction);
            default -> HttpResponse.badRequest(new ErrorResponse("unsupported interaction type"));
        };
    }

    private HttpResponse<InteractionResponse> handlePing() {
        // Respond with Pong - do NOT publish to Pub/Sub
        return HttpResponse.ok(new InteractionResponse(InteractionResponse.TYPE_PONG));
    }

    private HttpResponse<InteractionResponse> handleApplicationCommand(Interaction interaction) {
        // Publish to Pub/Sub asynchronously (if configured)
        if (pubSubService.isConfigured()) {
            pubSubService.publishAsync(interaction);
        }

        // Respond with deferred response
        return HttpResponse.ok(new InteractionResponse(InteractionResponse.TYPE_DEFERRED_CHANNEL_MESSAGE));
    }
}

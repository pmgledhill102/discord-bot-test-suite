package com.discord.webhook.controller;

import com.discord.webhook.model.ErrorResponse;
import com.discord.webhook.model.HealthResponse;
import com.discord.webhook.model.Interaction;
import com.discord.webhook.model.InteractionResponse;
import com.discord.webhook.service.PubSubService;
import com.discord.webhook.service.SignatureService;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
public class InteractionController {

  private static final String HEADER_SIGNATURE = "X-Signature-Ed25519";
  private static final String HEADER_TIMESTAMP = "X-Signature-Timestamp";

  private final SignatureService signatureService;
  private final PubSubService pubSubService;
  private final ObjectMapper objectMapper = new ObjectMapper();

  public InteractionController(SignatureService signatureService, PubSubService pubSubService) {
    this.signatureService = signatureService;
    this.pubSubService = pubSubService;
  }

  @GetMapping(value = "/health", produces = MediaType.APPLICATION_JSON_VALUE)
  public ResponseEntity<HealthResponse> health() {
    return ResponseEntity.ok(new HealthResponse("ok"));
  }

  @PostMapping(
      value = {"/", "/interactions"},
      consumes = MediaType.APPLICATION_JSON_VALUE,
      produces = MediaType.APPLICATION_JSON_VALUE)
  public ResponseEntity<?> handleInteraction(
      @RequestHeader(value = HEADER_SIGNATURE, required = false) String signature,
      @RequestHeader(value = HEADER_TIMESTAMP, required = false) String timestamp,
      @RequestBody byte[] body) {

    // Validate signature
    if (!signatureService.validateSignature(signature, timestamp, body)) {
      return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
          .body(new ErrorResponse("invalid signature"));
    }

    // Parse interaction
    Interaction interaction;
    try {
      interaction = objectMapper.readValue(body, Interaction.class);
    } catch (IOException e) {
      return ResponseEntity.badRequest().body(new ErrorResponse("invalid JSON"));
    }

    // Check for null body (JSON "null")
    if (interaction == null) {
      return ResponseEntity.badRequest().body(new ErrorResponse("invalid JSON"));
    }

    // Handle by type
    switch (interaction.getType()) {
      case Interaction.TYPE_PING:
        return handlePing();
      case Interaction.TYPE_APPLICATION_COMMAND:
        return handleApplicationCommand(interaction);
      default:
        return ResponseEntity.badRequest().body(new ErrorResponse("unsupported interaction type"));
    }
  }

  private ResponseEntity<InteractionResponse> handlePing() {
    // Respond with Pong - do NOT publish to Pub/Sub
    return ResponseEntity.ok(new InteractionResponse(InteractionResponse.TYPE_PONG));
  }

  private ResponseEntity<InteractionResponse> handleApplicationCommand(Interaction interaction) {
    // Publish to Pub/Sub asynchronously (if configured)
    if (pubSubService.isConfigured()) {
      pubSubService.publishAsync(interaction);
    }

    // Respond with deferred response
    return ResponseEntity.ok(
        new InteractionResponse(InteractionResponse.TYPE_DEFERRED_CHANNEL_MESSAGE));
  }
}

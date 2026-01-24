package com.discord.webhook.resource;

import com.discord.webhook.model.ErrorResponse;
import com.discord.webhook.model.HealthResponse;
import com.discord.webhook.model.Interaction;
import com.discord.webhook.model.InteractionResponse;
import com.discord.webhook.service.PubSubService;
import com.discord.webhook.service.SignatureService;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.inject.Inject;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.io.IOException;

@Path("/")
public class InteractionResource {

  private static final String HEADER_SIGNATURE = "X-Signature-Ed25519";
  private static final String HEADER_TIMESTAMP = "X-Signature-Timestamp";

  @Inject SignatureService signatureService;

  @Inject PubSubService pubSubService;

  private final ObjectMapper objectMapper = new ObjectMapper();

  @GET
  @Path("/health")
  @Produces(MediaType.APPLICATION_JSON)
  public Response health() {
    return Response.ok(new HealthResponse("ok")).build();
  }

  @POST
  @Consumes(MediaType.APPLICATION_JSON)
  @Produces(MediaType.APPLICATION_JSON)
  public Response handleInteraction(
      @HeaderParam(HEADER_SIGNATURE) String signature,
      @HeaderParam(HEADER_TIMESTAMP) String timestamp,
      byte[] body) {
    return processInteraction(signature, timestamp, body);
  }

  @POST
  @Path("/interactions")
  @Consumes(MediaType.APPLICATION_JSON)
  @Produces(MediaType.APPLICATION_JSON)
  public Response handleInteractionAlt(
      @HeaderParam(HEADER_SIGNATURE) String signature,
      @HeaderParam(HEADER_TIMESTAMP) String timestamp,
      byte[] body) {
    return processInteraction(signature, timestamp, body);
  }

  private Response processInteraction(String signature, String timestamp, byte[] body) {
    // Validate signature
    if (!signatureService.validateSignature(signature, timestamp, body)) {
      return Response.status(Response.Status.UNAUTHORIZED)
          .entity(new ErrorResponse("invalid signature"))
          .build();
    }

    // Parse interaction
    Interaction interaction;
    try {
      interaction = objectMapper.readValue(body, Interaction.class);
    } catch (IOException e) {
      return Response.status(Response.Status.BAD_REQUEST)
          .entity(new ErrorResponse("invalid JSON"))
          .build();
    }

    // Check for null body (JSON "null")
    if (interaction == null) {
      return Response.status(Response.Status.BAD_REQUEST)
          .entity(new ErrorResponse("invalid JSON"))
          .build();
    }

    // Handle by type
    return switch (interaction.getType()) {
      case Interaction.TYPE_PING -> handlePing();
      case Interaction.TYPE_APPLICATION_COMMAND -> handleApplicationCommand(interaction);
      default ->
          Response.status(Response.Status.BAD_REQUEST)
              .entity(new ErrorResponse("unsupported interaction type"))
              .build();
    };
  }

  private Response handlePing() {
    // Respond with Pong - do NOT publish to Pub/Sub
    return Response.ok(new InteractionResponse(InteractionResponse.TYPE_PONG)).build();
  }

  private Response handleApplicationCommand(Interaction interaction) {
    // Publish to Pub/Sub asynchronously (if configured)
    if (pubSubService.isConfigured()) {
      pubSubService.publishAsync(interaction);
    }

    // Respond with deferred response
    return Response.ok(new InteractionResponse(InteractionResponse.TYPE_DEFERRED_CHANNEL_MESSAGE))
        .build();
  }
}

package com.discord.webhook.resource;

import com.discord.webhook.model.ErrorResponse;
import com.discord.webhook.model.HealthResponse;
import com.discord.webhook.model.Interaction;
import com.discord.webhook.model.InteractionResponse;
import com.discord.webhook.service.PubSubService;
import com.discord.webhook.service.SignatureService;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.jboss.logging.Logger;

@Path("/")
@Produces(MediaType.APPLICATION_JSON)
public class InteractionResource {

  private static final Logger logger = Logger.getLogger(InteractionResource.class);
  private static final int INTERACTION_TYPE_PING = 1;
  private static final int INTERACTION_TYPE_APPLICATION_COMMAND = 2;

  @Inject SignatureService signatureService;

  @Inject PubSubService pubSubService;

  @GET
  @Path("/health")
  public Response health() {
    return Response.ok(new HealthResponse("healthy", "discord-webhook-quarkus-native")).build();
  }

  @POST
  @Consumes(MediaType.APPLICATION_JSON)
  public Response handleInteraction(
      @HeaderParam("X-Signature-Ed25519") String signature,
      @HeaderParam("X-Signature-Timestamp") String timestamp,
      String body) {

    // Validate required headers
    if (signature == null || signature.isEmpty()) {
      return Response.status(Response.Status.UNAUTHORIZED)
          .entity(new ErrorResponse("unauthorized", "Missing signature header"))
          .build();
    }

    if (timestamp == null || timestamp.isEmpty()) {
      return Response.status(Response.Status.UNAUTHORIZED)
          .entity(new ErrorResponse("unauthorized", "Missing timestamp header"))
          .build();
    }

    // Validate request body
    if (body == null || body.isEmpty()) {
      return Response.status(Response.Status.BAD_REQUEST)
          .entity(new ErrorResponse("bad_request", "Missing request body"))
          .build();
    }

    // Verify signature
    if (!signatureService.verifySignature(signature, timestamp, body)) {
      logger.warn("Invalid signature for request");
      return Response.status(Response.Status.UNAUTHORIZED)
          .entity(new ErrorResponse("unauthorized", "Invalid request signature"))
          .build();
    }

    // Parse interaction
    Interaction interaction;
    try {
      interaction =
          new com.fasterxml.jackson.databind.ObjectMapper().readValue(body, Interaction.class);
    } catch (Exception e) {
      logger.error("Failed to parse interaction: " + e.getMessage());
      return Response.status(Response.Status.BAD_REQUEST)
          .entity(new ErrorResponse("bad_request", "Invalid interaction payload"))
          .build();
    }

    // Check for null body (JSON "null" parses to null object)
    if (interaction == null) {
      return Response.status(Response.Status.BAD_REQUEST)
          .entity(new ErrorResponse("bad_request", "Invalid interaction payload"))
          .build();
    }

    // Handle ping
    if (interaction.getType() == INTERACTION_TYPE_PING) {
      logger.info("Handling ping interaction");
      return Response.ok(InteractionResponse.pong()).build();
    }

    // Handle application command
    if (interaction.getType() == INTERACTION_TYPE_APPLICATION_COMMAND) {
      logger.info("Handling application command interaction");

      // Publish to Pub/Sub asynchronously
      if (pubSubService.isConfigured()) {
        pubSubService.publishAsync(interaction);
      }

      // Return deferred response
      return Response.ok(InteractionResponse.deferredChannelMessage()).build();
    }

    // Unknown interaction type
    logger.warn("Unknown interaction type: " + interaction.getType());
    return Response.status(Response.Status.BAD_REQUEST)
        .entity(new ErrorResponse("bad_request", "Unknown interaction type"))
        .build();
  }
}

package com.discord.webhook.service;

import com.discord.webhook.model.Interaction;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.google.api.core.ApiFuture;
import com.google.api.core.ApiFutureCallback;
import com.google.api.core.ApiFutures;
import com.google.api.gax.core.NoCredentialsProvider;
import com.google.api.gax.grpc.GrpcTransportChannel;
import com.google.api.gax.rpc.FixedTransportChannelProvider;
import com.google.cloud.pubsub.v1.Publisher;
import com.google.common.util.concurrent.MoreExecutors;
import com.google.protobuf.ByteString;
import com.google.pubsub.v1.PubsubMessage;
import com.google.pubsub.v1.TopicName;
import io.grpc.ManagedChannel;
import io.grpc.ManagedChannelBuilder;
import io.quarkus.runtime.Shutdown;
import io.quarkus.runtime.Startup;
import jakarta.annotation.PostConstruct;
import jakarta.enterprise.context.ApplicationScoped;
import java.time.Instant;
import java.time.format.DateTimeFormatter;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.TimeUnit;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

@ApplicationScoped
@Startup
public class PubSubService {

  private static final Logger logger = Logger.getLogger(PubSubService.class);

  @ConfigProperty(name = "google.cloud.project")
  Optional<String> projectId;

  @ConfigProperty(name = "pubsub.topic")
  Optional<String> topicName;

  @ConfigProperty(name = "pubsub.emulator.host")
  Optional<String> emulatorHost;

  private Publisher publisher;
  private ManagedChannel channel;
  private final ObjectMapper objectMapper = new ObjectMapper();

  @PostConstruct
  public void init() {
    if (projectId.isEmpty()
        || topicName.isEmpty()
        || projectId.get().isEmpty()
        || topicName.get().isEmpty()) {
      logger.info("Pub/Sub not configured (missing project or topic)");
      return;
    }

    try {
      TopicName topic = TopicName.of(projectId.get(), topicName.get());
      Publisher.Builder publisherBuilder = Publisher.newBuilder(topic);

      // Configure for emulator if specified
      if (emulatorHost.isPresent() && !emulatorHost.get().isEmpty()) {
        channel = ManagedChannelBuilder.forTarget(emulatorHost.get()).usePlaintext().build();

        publisherBuilder
            .setChannelProvider(
                FixedTransportChannelProvider.create(GrpcTransportChannel.create(channel)))
            .setCredentialsProvider(NoCredentialsProvider.create());

        logger.info("Pub/Sub configured for emulator: " + emulatorHost.get());
      }

      publisher = publisherBuilder.build();
      logger.info("Pub/Sub publisher initialized for topic: " + topicName.get());
    } catch (Exception e) {
      logger.warn("Failed to initialize Pub/Sub publisher: " + e.getMessage());
    }
  }

  @Shutdown
  public void shutdown() {
    if (publisher != null) {
      try {
        publisher.shutdown();
        publisher.awaitTermination(10, TimeUnit.SECONDS);
      } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
        logger.warn("Interrupted while shutting down publisher");
      }
    }
    if (channel != null) {
      try {
        channel.shutdown();
        channel.awaitTermination(5, TimeUnit.SECONDS);
      } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
      }
    }
  }

  public boolean isConfigured() {
    return publisher != null;
  }

  public void publishAsync(Interaction interaction) {
    if (publisher == null) {
      return;
    }

    try {
      // Create sanitized copy (remove token)
      Interaction sanitized = interaction.createSanitizedCopy();
      String json = objectMapper.writeValueAsString(sanitized);

      // Build message with attributes
      PubsubMessage.Builder messageBuilder =
          PubsubMessage.newBuilder().setData(ByteString.copyFromUtf8(json));

      // Add attributes
      Map<String, String> attributes = messageBuilder.getMutableAttributes();
      if (interaction.getId() != null) {
        attributes.put("interaction_id", interaction.getId());
      }
      attributes.put("interaction_type", String.valueOf(interaction.getType()));
      if (interaction.getApplicationId() != null) {
        attributes.put("application_id", interaction.getApplicationId());
      }
      if (interaction.getGuildId() != null) {
        attributes.put("guild_id", interaction.getGuildId());
      }
      if (interaction.getChannelId() != null) {
        attributes.put("channel_id", interaction.getChannelId());
      }
      attributes.put("timestamp", DateTimeFormatter.ISO_INSTANT.format(Instant.now()));

      // Add command name if available
      if (interaction.getData() != null && interaction.getData().containsKey("name")) {
        Object name = interaction.getData().get("name");
        if (name instanceof String) {
          attributes.put("command_name", (String) name);
        }
      }

      PubsubMessage message = messageBuilder.build();
      ApiFuture<String> future = publisher.publish(message);

      ApiFutures.addCallback(
          future,
          new ApiFutureCallback<String>() {
            @Override
            public void onSuccess(String messageId) {
              logger.debug("Published message: " + messageId);
            }

            @Override
            public void onFailure(Throwable t) {
              logger.error("Failed to publish message: " + t.getMessage());
            }
          },
          MoreExecutors.directExecutor());

    } catch (JsonProcessingException e) {
      logger.error("Failed to serialize interaction: " + e.getMessage());
    }
  }
}

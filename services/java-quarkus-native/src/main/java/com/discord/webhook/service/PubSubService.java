package com.discord.webhook.service;

import com.discord.webhook.model.Interaction;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.quarkus.runtime.Startup;
import jakarta.annotation.PostConstruct;
import jakarta.enterprise.context.ApplicationScoped;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.time.Instant;
import java.time.format.DateTimeFormatter;
import java.util.Base64;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;

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

    private HttpClient httpClient;
    private final ObjectMapper objectMapper = new ObjectMapper();
    private String publishUrl;
    private boolean configured = false;

    @PostConstruct
    public void init() {
        if (projectId.isEmpty() || topicName.isEmpty() ||
            projectId.get().isEmpty() || topicName.get().isEmpty()) {
            logger.info("Pub/Sub not configured (missing project or topic)");
            return;
        }

        if (emulatorHost.isEmpty() || emulatorHost.get().isEmpty()) {
            logger.info("Pub/Sub emulator host not configured");
            return;
        }

        // Build the REST API URL for publishing
        // Format: http://{emulator}/v1/projects/{project}/topics/{topic}:publish
        String host = emulatorHost.get();
        if (!host.startsWith("http://") && !host.startsWith("https://")) {
            host = "http://" + host;
        }
        publishUrl = String.format("%s/v1/projects/%s/topics/%s:publish",
                host, projectId.get(), topicName.get());

        httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(10))
                .build();

        configured = true;
        logger.info("Pub/Sub HTTP client configured for: " + publishUrl);
    }

    public boolean isConfigured() {
        return configured;
    }

    public void publishAsync(Interaction interaction) {
        if (!configured) {
            return;
        }

        CompletableFuture.runAsync(() -> {
            try {
                publish(interaction);
            } catch (Exception e) {
                logger.error("Failed to publish message: " + e.getMessage());
            }
        });
    }

    private void publish(Interaction interaction) throws Exception {
        // Create sanitized copy (remove token)
        Interaction sanitized = interaction.createSanitizedCopy();
        String json = objectMapper.writeValueAsString(sanitized);

        // Build attributes
        Map<String, String> attributes = new HashMap<>();
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

        // Build Pub/Sub REST API request body
        // Format: {"messages": [{"data": "base64-encoded", "attributes": {...}}]}
        Map<String, Object> message = new HashMap<>();
        message.put("data", Base64.getEncoder().encodeToString(json.getBytes()));
        message.put("attributes", attributes);

        Map<String, Object> requestBody = new HashMap<>();
        requestBody.put("messages", List.of(message));

        String requestJson = objectMapper.writeValueAsString(requestBody);

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(publishUrl))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(requestJson))
                .timeout(Duration.ofSeconds(10))
                .build();

        HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

        if (response.statusCode() >= 200 && response.statusCode() < 300) {
            logger.debug("Published message to Pub/Sub via HTTP");
        } else {
            logger.error("Failed to publish to Pub/Sub: HTTP " + response.statusCode() + " - " + response.body());
        }
    }
}

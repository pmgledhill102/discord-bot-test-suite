# frozen_string_literal: true

require "json"
require "time"

# Publishes sanitized Discord interactions to Google Cloud Pub/Sub.
# Sensitive fields like tokens are stripped before publishing.
class PubsubPublisher
  class << self
    def instance
      @instance ||= new
    end

    def publish(interaction)
      instance.publish(interaction)
    end

    def configured?
      instance.configured?
    end
  end

  def initialize
    @publisher = nil
    @topic_path = nil
    @configured = false
    setup_client
  end

  def configured?
    @configured
  end

  def publish(interaction)
    return unless @configured && @publisher && @topic_path

    Thread.new do
      publish_sync(interaction)
    end
  end

  private

  def setup_client
    project_id = ENV.fetch("GOOGLE_CLOUD_PROJECT", nil)
    topic_name = ENV.fetch("PUBSUB_TOPIC", nil)

    return unless project_id && topic_name

    begin
      require "google/cloud/pubsub"
      @publisher = Google::Cloud::PubSub.new(project_id: project_id)
      @topic_path = topic_name
      ensure_topic_exists
      @configured = true
      Rails.logger.info("Pub/Sub configured: #{project_id}/#{topic_name}")
    rescue StandardError => e
      Rails.logger.warn("Failed to initialize Pub/Sub client: #{e.message}")
      @publisher = nil
      @topic_path = nil
      @configured = false
    end
  end

  def ensure_topic_exists
    topic = @publisher.topic(@topic_path)
    return if topic

    @publisher.create_topic(@topic_path)
    Rails.logger.info("Created topic: #{@topic_path}")
  rescue StandardError => e
    Rails.logger.warn("Failed to create topic: #{e.message}")
  end

  def publish_sync(interaction)
    topic = @publisher.topic(@topic_path)
    return unless topic

    sanitized = sanitize_interaction(interaction)
    data = JSON.generate(sanitized)
    attributes = build_attributes(interaction)

    topic.publish(data, attributes)
  rescue StandardError => e
    Rails.logger.error("Failed to publish to Pub/Sub: #{e.message}")
  end

  def sanitize_interaction(interaction)
    # Create sanitized copy without sensitive fields (token is intentionally omitted)
    {
      "type" => interaction["type"],
      "id" => interaction["id"],
      "application_id" => interaction["application_id"],
      "data" => interaction["data"],
      "guild_id" => interaction["guild_id"],
      "channel_id" => interaction["channel_id"],
      "member" => interaction["member"],
      "user" => interaction["user"],
      "locale" => interaction["locale"],
      "guild_locale" => interaction["guild_locale"]
    }.compact
  end

  def build_attributes(interaction)
    attrs = {
      "interaction_id" => interaction["id"].to_s,
      "interaction_type" => interaction["type"].to_s,
      "application_id" => interaction["application_id"].to_s,
      "guild_id" => interaction["guild_id"].to_s,
      "channel_id" => interaction["channel_id"].to_s,
      "timestamp" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    }

    # Add command name if available
    if interaction["data"].is_a?(Hash) && interaction["data"]["name"]
      attrs["command_name"] = interaction["data"]["name"]
    end

    attrs
  end
end

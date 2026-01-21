# frozen_string_literal: true

require "ed25519"
require "json"

# Handles Discord interactions webhook requests.
# Validates Ed25519 signatures and responds to Ping/Slash commands.
class InteractionsController < ApplicationController
  # Interaction types
  INTERACTION_TYPE_PING = 1
  INTERACTION_TYPE_APPLICATION_COMMAND = 2

  # Response types
  RESPONSE_TYPE_PONG = 1
  RESPONSE_TYPE_DEFERRED_CHANNEL_MESSAGE = 5

  # Maximum age for timestamp validation (seconds)
  TIMESTAMP_MAX_AGE = 5

  before_action :load_raw_body
  before_action :validate_signature

  def create
    interaction = parse_interaction
    return render json: { error: "invalid JSON" }, status: :bad_request unless interaction

    case interaction["type"]
    when INTERACTION_TYPE_PING
      handle_ping
    when INTERACTION_TYPE_APPLICATION_COMMAND
      handle_application_command(interaction)
    else
      render json: { error: "unsupported interaction type" }, status: :bad_request
    end
  end

  private

  def load_raw_body
    @raw_body = request.body.read
    request.body.rewind
  end

  def validate_signature
    signature_hex = request.headers["X-Signature-Ed25519"]
    timestamp = request.headers["X-Signature-Timestamp"]

    unless valid_signature?(signature_hex, timestamp, @raw_body)
      render json: { error: "invalid signature" }, status: :unauthorized
    end
  end

  def valid_signature?(signature_hex, timestamp, body)
    return false if signature_hex.blank? || timestamp.blank?
    return false unless valid_timestamp?(timestamp)

    public_key = discord_public_key
    return false unless public_key

    begin
      signature = [signature_hex].pack("H*")
      message = timestamp + body

      verify_key = Ed25519::VerifyKey.new(public_key)
      verify_key.verify(signature, message)
      true
    rescue ArgumentError, Ed25519::VerifyError
      false
    end
  end

  def valid_timestamp?(timestamp)
    ts = Integer(timestamp)
    (Time.now.to_i - ts) <= TIMESTAMP_MAX_AGE
  rescue ArgumentError, TypeError
    false
  end

  def discord_public_key
    @discord_public_key ||= begin
      hex = ENV.fetch("DISCORD_PUBLIC_KEY", nil)
      return nil unless hex

      [hex].pack("H*")
    rescue ArgumentError
      nil
    end
  end

  def parse_interaction
    parsed = JSON.parse(@raw_body)
    # Ensure interaction is a Hash (not null, array, or primitive)
    parsed.is_a?(Hash) ? parsed : nil
  rescue JSON::ParserError
    nil
  end

  def handle_ping
    render json: { type: RESPONSE_TYPE_PONG }
  end

  def handle_application_command(interaction)
    # Publish to Pub/Sub in background thread
    PubsubPublisher.publish(interaction) if PubsubPublisher.configured?

    # Respond with deferred response (non-ephemeral)
    render json: { type: RESPONSE_TYPE_DEFERRED_CHANNEL_MESSAGE }
  end
end

# frozen_string_literal: true

require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Set a dummy secret_key_base since we don't use sessions/cookies
  config.secret_key_base = ENV.fetch("SECRET_KEY_BASE") { SecureRandom.hex(64) }

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings
  config.eager_load = true

  # Full error reports are disabled
  config.consider_all_requests_local = false

  # Disable caching
  config.action_controller.perform_caching = false

  # Do not fallback to assets pipeline if a precompiled asset is missed.
  config.assets.compile = false if config.respond_to?(:assets)

  # Enable locale fallbacks for I18n
  config.i18n.fallbacks = true

  # Don't log any deprecations
  config.active_support.report_deprecations = false

  # Use default logging formatter
  config.log_formatter = ::Logger::Formatter.new
  config.log_level = :info

  # Log to STDOUT
  config.logger = ActiveSupport::TaggedLogging.logger($stdout)
end

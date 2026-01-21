# frozen_string_literal: true

require_relative "boot"

require "rails"
require "action_controller/railtie"

# Require the gems listed in Gemfile
Bundler.require(*Rails.groups)

module DiscordWebhook
  class Application < Rails::Application
    config.load_defaults 8.0

    # API-only mode
    config.api_only = true

    # Disable unnecessary middleware for minimal footprint
    config.middleware.delete ActionDispatch::Cookies
    config.middleware.delete ActionDispatch::Session::CookieStore
    config.middleware.delete ActionDispatch::Flash

    # Autoload paths
    config.autoload_paths << Rails.root.join("app/services")

    # Configure logging
    config.log_level = :info
    config.log_formatter = ::Logger::Formatter.new

    # Use STDOUT for logging in production
    if ENV["RAILS_LOG_TO_STDOUT"].present? || Rails.env.production?
      logger = ActiveSupport::Logger.new($stdout)
      logger.formatter = config.log_formatter
      config.logger = ActiveSupport::TaggedLogging.new(logger)
    end
  end
end

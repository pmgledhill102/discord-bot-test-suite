# frozen_string_literal: true

require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Reload code on each request
  config.enable_reloading = true

  # Do not eager load code on boot
  config.eager_load = false

  # Show full error reports
  config.consider_all_requests_local = true

  # Disable caching
  config.action_controller.perform_caching = false

  # Print deprecation notices to the Rails logger
  config.active_support.deprecation = :log

  # Use default logging formatter
  config.log_formatter = ::Logger::Formatter.new
  config.log_level = :debug
end

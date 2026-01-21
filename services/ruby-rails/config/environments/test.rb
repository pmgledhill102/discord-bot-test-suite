# frozen_string_literal: true

require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Do not reload code
  config.enable_reloading = false

  # Eager load for test
  config.eager_load = ENV["CI"].present?

  # Show full error reports
  config.consider_all_requests_local = true

  # Disable caching
  config.action_controller.perform_caching = false

  # Raise on deprecations
  config.active_support.deprecation = :raise

  # Use default logging formatter
  config.log_formatter = ::Logger::Formatter.new
  config.log_level = :debug
end

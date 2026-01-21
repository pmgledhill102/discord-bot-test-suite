# frozen_string_literal: true

# Puma configuration for production

# Specifies the `port` that Puma will listen on
port ENV.fetch("PORT", 8080)

# Specifies the `environment` that Puma will run in
environment ENV.fetch("RAILS_ENV", "production")

# Use single worker for Cloud Run (scales via instances, not workers)
workers 0

# Use threads for concurrent request handling
threads_count = ENV.fetch("RAILS_MAX_THREADS", 4).to_i
threads threads_count, threads_count

# Preload for faster worker spawning
preload_app!

# Allow puma to be restarted by `rails restart` command
plugin :tmp_restart

# Logging
stdout_redirect nil, nil, true

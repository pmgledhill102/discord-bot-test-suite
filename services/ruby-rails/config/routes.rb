# frozen_string_literal: true

Rails.application.routes.draw do
  # Health check endpoint
  get "/health", to: "health#show"

  # Discord webhook endpoints
  post "/", to: "interactions#create"
  post "/interactions", to: "interactions#create"
end

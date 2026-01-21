"""URL configuration for discord_webhook service."""

from django.urls import path

from . import views

urlpatterns = [
    path("health", views.health, name="health"),
    path("", views.handle_interaction, name="interaction_root"),
    path("interactions", views.handle_interaction, name="interaction"),
]

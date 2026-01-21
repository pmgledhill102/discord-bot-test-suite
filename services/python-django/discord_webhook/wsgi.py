"""WSGI config for discord_webhook service.

It exposes the WSGI callable as a module-level variable named ``application``.
"""

import os

from django.core.wsgi import get_wsgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "discord_webhook.settings")

application = get_wsgi_application()

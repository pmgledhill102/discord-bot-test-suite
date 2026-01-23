# Build stage - install dependencies
FROM composer:2 AS composer

WORKDIR /app

# Create required Laravel directories
RUN mkdir -p bootstrap/cache storage/framework/{cache,sessions,views} storage/logs

# Copy composer files
COPY composer.json ./

# Install dependencies (skip scripts to avoid running artisan before app is ready)
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist

# Copy application code
COPY . .

# Generate optimized autoloader (skip scripts)
RUN composer dump-autoload --optimize --no-dev --no-scripts

# Cache configuration and routes for faster boot
RUN php artisan config:cache && php artisan route:cache

# Runtime stage
FROM php:8.5-cli-alpine

# Install required extensions and CA certificates
# Note: OPcache is built into PHP and configured via opcache.ini
RUN apk add --no-cache \
    ca-certificates \
    libsodium \
    && docker-php-ext-enable sodium

# Copy OPcache configuration
COPY opcache.ini /usr/local/etc/php/conf.d/opcache.ini

# Set working directory
WORKDIR /app

# Copy application from composer stage
COPY --from=composer /app /app

# Copy preload script
COPY preload.php /app/preload.php

# Create storage and bootstrap cache directories and set permissions
RUN mkdir -p bootstrap/cache storage/framework/{cache,sessions,views} storage/logs \
    && chmod -R 777 storage bootstrap/cache

# Expose port
EXPOSE 8080

# Reduce memory fragmentation in glibc malloc
ENV MALLOC_ARENA_MAX=2

# Use PHP's built-in server
ENV PORT=8080
CMD ["sh", "-c", "php artisan serve --host=0.0.0.0 --port=${PORT}"]

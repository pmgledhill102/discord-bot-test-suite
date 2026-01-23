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

# Runtime stage
FROM php:8.5-cli-alpine

# Install required extensions and CA certificates
RUN apk add --no-cache \
    ca-certificates \
    libsodium \
    && docker-php-ext-enable sodium

# Set working directory
WORKDIR /app

# Copy application from composer stage
COPY --from=composer /app /app

# Create storage and bootstrap cache directories and set permissions
RUN mkdir -p bootstrap/cache storage/framework/{cache,sessions,views} storage/logs \
    && chmod -R 777 storage bootstrap/cache

# Expose port
EXPOSE 8080

# Use PHP's built-in server
ENV PORT=8080
CMD ["sh", "-c", "php artisan serve --host=0.0.0.0 --port=${PORT}"]

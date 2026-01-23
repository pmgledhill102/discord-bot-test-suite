# PHP Container Optimization

## Services

| Service     | Current Base       | Current Size | Cold Start | Target Base | Target Size |
| ----------- | ------------------ | ------------ | ---------- | ----------- | ----------- |
| php-laravel | php:8.5-cli-alpine | 47 MB        | 1.62s      | php:alpine  | TBD         |

## Current State

- Already using php:alpine (good base choice)
- No distroless available for PHP
- Multi-stage build with composer

## Optimization Tasks

### 1. Add OPcache Preloading

- [ ] Configure OPcache for preloading

**Implementation:**

```dockerfile
# Add to php.ini or via environment
ENV PHP_OPCACHE_PRELOAD=/app/preload.php
ENV PHP_OPCACHE_PRELOAD_USER=www-data
```

### 2. Add Config Caching

- [ ] Run `php artisan config:cache` at build time

**Implementation:**

```dockerfile
RUN php artisan config:cache
```

### 3. Add Route Caching

- [ ] Run `php artisan route:cache` at build time

**Implementation:**

```dockerfile
RUN php artisan route:cache
```

### 4. Runtime Configuration

- [ ] Add `ENV MALLOC_ARENA_MAX=2`

## Progress Log

### 2026-01-23 - Baseline

- Measured baseline size: 47 MB (already reasonable)
- Cold start: 1.62s
- Already using Alpine, focus on runtime optimization

## Files to Modify

- `services/php-laravel/Dockerfile`

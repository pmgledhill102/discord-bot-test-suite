# Ruby Container Optimization

## Services

| Service    | Current Base  | Current Size | Cold Start | Target Base | Target Size |
| ---------- | ------------- | ------------ | ---------- | ----------- | ----------- |
| ruby-rails | ruby:3.4-slim | 222 MB       | N/A\*      | ruby:alpine | TBD         |

\*Cold start test failed (401 error)

## Current State

- Using ruby:3.4-slim (largest image at 222 MB)
- No distroless available for Ruby
- Multi-stage build with pre-built gem preference

## Optimization Tasks

### 1. Evaluate Alpine Base

- [ ] Test `ruby:3.4-alpine` compatibility
- [ ] Verify grpc gem works with musl

**Considerations:**

- grpc gem native extension may have issues with musl
- May need to compile from source (slow build)
- libyaml availability on Alpine

**Implementation:**

```dockerfile
FROM ruby:3.4-alpine
RUN apk add --no-cache build-base
```

### 2. Add Bootsnap Precompilation

- [ ] Enable Bootsnap cache precompilation at build time

**Implementation:**

```dockerfile
RUN bundle exec bootsnap precompile --gemfile app/
```

### 3. Clean Gem Build Artifacts

- [ ] Remove unnecessary files after gem install

**Implementation:**

```dockerfile
RUN rm -rf vendor/bundle/ruby/*/cache \
    && rm -rf vendor/bundle/ruby/*/gems/*/spec \
    && rm -rf vendor/bundle/ruby/*/gems/*/test
```

## Progress Log

### 2026-01-23 - Baseline

- Measured baseline size: 222 MB (largest of all services)
- Cold start test failing (401 error)
- Priority: Significant size reduction potential

## Files to Modify

- `services/ruby-rails/Dockerfile`

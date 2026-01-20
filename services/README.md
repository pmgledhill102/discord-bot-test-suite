# Services

This directory contains Discord webhook service implementations across multiple languages and frameworks.

Each service implements the same contract:
1. Validate Ed25519 signature on incoming requests
2. Respond to Ping (type=1) with Pong (type=1)
3. Respond to Slash commands (type=2) with deferred response (type=5)
4. Publish sanitized slash command payloads to Pub/Sub

## Service Directory Structure

Each service directory should contain:
- `Dockerfile` - Container build instructions
- `.gitignore` - Language-specific ignore patterns
- Language-appropriate project files (go.mod, requirements.txt, etc.)
- Source code

## Planned Implementations

| Directory | Language | Framework |
|-----------|----------|-----------|
| `go-gin/` | Go | Gin |
| `python-django/` | Python | Django |
| `python-flask/` | Python | Flask |
| `node-express/` | Node.js | Express |
| `java-spring/` | Java | Spring Boot |
| `rust-actix/` | Rust | Actix-web |
| `csharp-aspnet/` | C# | ASP.NET Core |
| `ruby-rails/` | Ruby | Rails |
| `php-laravel/` | PHP | Laravel |
| `cpp-drogon/` | C++ | Drogon |

## Federated .gitignore Strategy

The root `.gitignore` handles shared patterns (IDE, env, logs). Each service has its own `.gitignore` for language-specific artifacts.

### .gitignore Templates

#### Go (`go-gin/`)
```gitignore
# Build output
/bin/
*.exe

# Test artifacts
*.test
coverage.out
coverage.html

# Dependency cache (if vendoring)
/vendor/
```

#### Python (`python-django/`, `python-flask/`)
```gitignore
# Byte-compiled files
__pycache__/
*.py[cod]
*$py.class

# Virtual environment
.venv/
venv/
env/

# Testing
.coverage
htmlcov/
.pytest_cache/

# Type checking
.mypy_cache/
```

#### Node.js (`node-express/`)
```gitignore
# Dependencies
node_modules/

# Build output
dist/
build/

# Runtime
.npm
*.tsbuildinfo
```

#### Java (`java-spring/`)
```gitignore
# Build output
target/
build/
*.class
*.jar
*.war

# IDE
.gradle/
.mvn/wrapper/maven-wrapper.jar

# Logs
*.log
```

#### Rust (`rust-actix/`)
```gitignore
# Build output
/target/

# Cargo lock is committed for binaries
# Cargo.lock - keep for reproducible builds
```

#### C# (`csharp-aspnet/`)
```gitignore
# Build output
bin/
obj/

# NuGet
*.nupkg
*.snupkg

# User settings
*.user
*.suo
```

#### Ruby (`ruby-rails/`)
```gitignore
# Bundler
.bundle/
vendor/bundle/

# Runtime
log/
tmp/
storage/

# Environment
.env*.local
```

#### PHP (`php-laravel/`)
```gitignore
# Dependencies
/vendor/

# Environment
.env

# Cache
bootstrap/cache/*
storage/*.key

# Runtime
storage/logs/
```

#### C++ (`cpp-drogon/`)
```gitignore
# Build output
/build/
*.o
*.obj
*.a
*.lib
*.so
*.dylib

# CMake
CMakeCache.txt
CMakeFiles/
cmake_install.cmake
Makefile
```

## Environment Variables

All services must support these environment variables:

| Variable | Description |
|----------|-------------|
| `PORT` | HTTP server port (default: 8080) |
| `DISCORD_PUBLIC_KEY` | Ed25519 public key for signature validation |
| `PUBSUB_TOPIC` | Pub/Sub topic for publishing slash commands |
| `PUBSUB_EMULATOR_HOST` | Pub/Sub emulator endpoint (local dev only) |
| `GOOGLE_CLOUD_PROJECT` | GCP project ID |

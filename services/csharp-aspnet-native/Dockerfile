# Multi-stage build for .NET Native AOT
#
# Native AOT produces a self-contained executable that doesn't require
# the .NET runtime, resulting in faster cold-start times and smaller images.

# Build stage: .NET SDK with native compilation tools
FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine AS builder

# Install native compilation dependencies
RUN apk add --no-cache clang build-base zlib-dev

WORKDIR /app

# Copy project file first for better layer caching
COPY *.csproj ./
RUN dotnet restore

# Copy source code
COPY . .

# Publish with Native AOT
RUN dotnet publish -c Release -o out

# Runtime stage: minimal image (no .NET runtime needed)
FROM mcr.microsoft.com/dotnet/runtime-deps:10.0-alpine

# Install libsodium for Ed25519 signature validation (NSec.Cryptography dependency)
# Create symlink for unversioned library name (NSec looks for libsodium.so)
RUN apk add --no-cache libsodium && \
    ln -s /usr/lib/libsodium.so.26 /usr/lib/libsodium.so

WORKDIR /app

# Copy the native binary
COPY --from=builder /app/out/DiscordWebhookNative /app/

# Non-root user for security
USER 1000

# Expose port
EXPOSE 8080

# Run the native binary directly
ENTRYPOINT ["./DiscordWebhookNative"]

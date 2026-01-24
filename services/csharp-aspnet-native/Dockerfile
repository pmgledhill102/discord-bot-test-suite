# Multi-stage build for .NET Native AOT
#
# Native AOT produces a self-contained executable that doesn't require
# the .NET runtime, resulting in faster cold-start times and smaller images.

# Build stage: .NET SDK with native compilation tools (Ubuntu for glibc compatibility)
FROM mcr.microsoft.com/dotnet/sdk:10.0-noble AS builder

# Install native compilation dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    clang \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy project file first for better layer caching
COPY *.csproj ./
RUN dotnet restore

# Copy source code
COPY . .

# Publish with Native AOT
RUN dotnet publish -c Release -o out

# Library stage: build libsodium 1.0.20 from source (NSec requires >= 1.0.20)
FROM ubuntu:24.04 AS libs

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && curl -L https://download.libsodium.org/libsodium/releases/libsodium-1.0.20-stable.tar.gz | tar xz \
    && cd libsodium-stable \
    && ./configure --prefix=/usr --disable-static \
    && make -j$(nproc) \
    && make install \
    && mkdir -p /staging/lib \
    && cp /usr/lib/libsodium.so.26* /staging/lib/ \
    && ln -s libsodium.so.26 /staging/lib/libsodium.so

# Runtime stage: Microsoft chiseled image (distroless-like, non-root by default)
FROM mcr.microsoft.com/dotnet/runtime-deps:10.0-noble-chiseled

# Reduce glibc memory allocator arena count for lower memory usage
ENV MALLOC_ARENA_MAX=2

WORKDIR /app

# Copy libsodium from libs stage (NSec.Cryptography dependency for Ed25519)
COPY --from=libs /staging/lib/libsodium* /usr/lib/

# Copy the native binary
COPY --from=builder /app/out/DiscordWebhookNative /app/

# Expose port (chiseled images run as non-root by default)
EXPOSE 8080

# Run the native binary directly
ENTRYPOINT ["./DiscordWebhookNative"]

# C++/Drogon Discord webhook service
# Multi-stage build for smaller final image

# Build stage
FROM ubuntu:24.04 AS builder

# Avoid prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    pkg-config \
    libsodium-dev \
    libjsoncpp-dev \
    uuid-dev \
    zlib1g-dev \
    libssl-dev \
    libpq-dev \
    libmariadb-dev \
    libsqlite3-dev \
    libhiredis-dev \
    libc-ares-dev \
    libbrotli-dev \
    && rm -rf /var/lib/apt/lists/*

# Build and install Drogon
WORKDIR /tmp
RUN git clone --depth 1 --branch v1.9.11 https://github.com/drogonframework/drogon.git && \
    cd drogon && \
    git submodule update --init && \
    mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_EXAMPLES=OFF -DBUILD_CTL=OFF -DBUILD_ORM=OFF && \
    make -j$(nproc) && \
    make install && \
    cd /tmp && rm -rf drogon

# Copy and build application
WORKDIR /app
COPY CMakeLists.txt main.cc ./

RUN mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release && \
    make -j$(nproc)

# Runtime stage
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install runtime dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsodium23 \
    libjsoncpp25 \
    libuuid1 \
    zlib1g \
    libssl3 \
    libc-ares2 \
    libbrotli1 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy binary from builder
COPY --from=builder /app/build/server /server

# Expose port
EXPOSE 8080

# Run the server
ENTRYPOINT ["/server"]

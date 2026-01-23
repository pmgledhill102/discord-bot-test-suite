# C++/Drogon Discord webhook service
# Multi-stage build with distroless runtime for minimal image size

# Build stage - using Debian bookworm to match distroless/cc-debian12
FROM debian:bookworm AS builder

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
    libc-ares-dev \
    libbrotli-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Build and install Drogon as shared library
WORKDIR /tmp
RUN git clone --depth 1 --branch v1.9.11 https://github.com/drogonframework/drogon.git && \
    cd drogon && \
    git submodule update --init && \
    mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_EXAMPLES=OFF \
        -DBUILD_CTL=OFF \
        -DBUILD_ORM=OFF \
        -DBUILD_SHARED_LIBS=ON && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    cd /tmp && rm -rf drogon

# Copy and build application
WORKDIR /app
COPY CMakeLists.txt main.cc ./

RUN mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release && \
    make -j$(nproc)

# Strip debug symbols from binary for smaller size
RUN strip --strip-all /app/build/server

# Collect shared library dependencies into a staging directory
# Libraries are placed in /lib to work with distroless's ld.so configuration
RUN mkdir -p /staging/lib && \
    # Copy all required shared libraries to /lib
    ldd /app/build/server | grep "=> /" | awk '{print $3}' | while read lib; do \
        cp -L "$lib" /staging/lib/; \
    done && \
    # Also copy Drogon and Trantor shared libraries from /usr/local/lib
    cp -L /usr/local/lib/libdrogon.so* /staging/lib/ && \
    cp -L /usr/local/lib/libtrantor.so* /staging/lib/ && \
    # Strip the copied libraries to reduce size
    find /staging -name "*.so*" -exec strip --strip-unneeded {} \; 2>/dev/null || true

# Runtime stage - using distroless/cc for minimal attack surface
FROM gcr.io/distroless/cc-debian12

# Copy CA certificates for HTTPS (Pub/Sub communication)
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy all shared libraries to /lib which is in distroless's library search path
# distroless/cc includes: glibc, libgcc, libstdc++
# We copy: libsodium, libjsoncpp, libuuid, zlib, libssl, libcrypto, libc-ares, libbrotli, drogon, trantor
COPY --from=builder /staging/lib/ /lib/

# Copy stripped binary from builder
COPY --from=builder /app/build/server /server

# Expose port
EXPOSE 8080

# Run the server
ENTRYPOINT ["/server"]

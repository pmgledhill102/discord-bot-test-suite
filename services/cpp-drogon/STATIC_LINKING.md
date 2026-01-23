<!-- cspell:ignore libtrantor libdrogon libcares jsoncpp DCMAKE -->

# Static Linking Investigation for cpp-drogon

This document captures the investigation into static linking for the cpp-drogon service
as part of container optimization efforts.

## Goal

Determine if Drogon can be statically linked to enable use of `gcr.io/distroless/static`
or `scratch` base images, which would further reduce image size and attack surface.

## Current State

The service currently uses dynamic linking with the following dependencies:

- libsodium (Ed25519 signature verification)
- libjsoncpp (JSON parsing)
- libuuid (UUID generation)
- zlib (compression)
- libssl/libcrypto (TLS/crypto)
- libc-ares (async DNS)
- libbrotli (compression)
- libtrantor (Drogon's underlying network library)
- libdrogon (Drogon framework)

## Static Linking Approach

To achieve static linking, the following CMake flags would be needed:

```cmake
# In CMakeLists.txt
set(CMAKE_EXE_LINKER_FLAGS "-static")
set(CMAKE_FIND_LIBRARY_SUFFIXES ".a")

# Or via command line
cmake .. -DCMAKE_EXE_LINKER_FLAGS="-static" -DCMAKE_FIND_LIBRARY_SUFFIXES=".a"
```

## Challenges

### 1. Static Library Availability

Not all dependencies provide static libraries (.a files) in standard packages:

- `libsodium-dev` - provides libsodium.a ✓
- `libjsoncpp-dev` - provides libjsoncpp.a ✓
- `zlib1g-dev` - provides libz.a ✓
- `libssl-dev` - provides libssl.a, libcrypto.a ✓
- `libc-ares-dev` - provides libcares.a ✓
- `libbrotli-dev` - provides static libs ✓

### 2. Drogon Static Build

Drogon must be built as a static library:

```bash
cmake .. -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_CTL=OFF \
    -DBUILD_ORM=OFF \
    -DBUILD_SHARED_LIBS=OFF
```

### 3. glibc Static Linking Issues

Static linking with glibc is problematic:

- NSS (Name Service Switch) requires dynamic loading
- DNS resolution may fail at runtime
- Thread-local storage issues

Alternative: Use musl-libc (Alpine-based build) for true static binary.

### 4. OpenSSL Static Linking

OpenSSL static linking requires careful handling of:

- Engine loading (dynamic by default)
- Certificate loading paths

## Recommended Approach for Full Static Linking

If static linking is desired, use Alpine Linux with musl:

```dockerfile
FROM alpine:3.21 AS builder

RUN apk add --no-cache \
    build-base \
    cmake \
    git \
    libsodium-dev \
    libsodium-static \
    jsoncpp-dev \
    jsoncpp-static \
    util-linux-dev \
    zlib-dev \
    zlib-static \
    openssl-dev \
    openssl-libs-static \
    c-ares-dev \
    c-ares-static \
    brotli-dev \
    brotli-static

# Build Drogon statically
RUN git clone --depth 1 --branch v1.9.11 https://github.com/drogonframework/drogon.git && \
    cd drogon && \
    git submodule update --init && \
    mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_EXAMPLES=OFF \
        -DBUILD_CTL=OFF \
        -DBUILD_ORM=OFF \
        -DBUILD_SHARED_LIBS=OFF && \
    make -j$(nproc) && \
    make install

# Build application statically
WORKDIR /app
COPY CMakeLists.txt main.cc ./
RUN mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_EXE_LINKER_FLAGS="-static" \
        -DCMAKE_FIND_LIBRARY_SUFFIXES=".a" && \
    make -j$(nproc) && \
    strip --strip-all server

# Runtime - scratch or distroless/static
FROM scratch
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /app/build/server /server
EXPOSE 8080
ENTRYPOINT ["/server"]
```

## Conclusion

**Current recommendation**: Use `gcr.io/distroless/cc-debian12` with dynamic linking.

**Rationale**:

1. Distroless/cc already provides significant size reduction
2. Static linking with glibc has runtime risks (DNS, NSS)
3. Switching to musl/Alpine may introduce compatibility issues
4. The complexity/risk of static linking outweighs the marginal size benefit

**Future consideration**: If image size becomes critical, the Alpine/musl approach
documented above can be implemented, but should be thoroughly tested for:

- DNS resolution under various network conditions
- TLS/SSL certificate handling
- Thread safety under load

## Size Comparison (Estimated)

| Configuration                        | Estimated Image Size |
| ------------------------------------ | -------------------- |
| ubuntu:24.04 runtime                 | ~180MB               |
| distroless/cc-debian12 + shared libs | ~50-70MB             |
| distroless/static (full static)      | ~25-35MB             |
| scratch (full static, musl)          | ~20-30MB             |

The distroless/cc approach achieves ~65% size reduction with minimal risk.

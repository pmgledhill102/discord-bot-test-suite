# Build stage
FROM mcr.microsoft.com/dotnet/sdk:10.0-noble AS builder

WORKDIR /app

# Copy project file first for better layer caching
COPY *.csproj ./
RUN dotnet restore

# Copy source code
COPY . .

# Build the application with ReadyToRun compilation for faster cold starts
# R2R pre-compiles IL to native code, reducing JIT time at startup
# Note: R2R requires specifying runtime; TARGETARCH is set by BuildKit
ARG TARGETARCH
RUN if [ "$TARGETARCH" = "amd64" ]; then RID="linux-x64"; else RID="linux-arm64"; fi && \
    dotnet publish -c Release -o out \
    -p:PublishReadyToRun=true \
    --runtime $RID \
    --no-self-contained

# Runtime stage - Microsoft chiseled image (distroless-like, non-root by default)
FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled

# Reduce glibc memory allocator arena count for lower memory usage
ENV MALLOC_ARENA_MAX=2

WORKDIR /app

# Copy the published output
COPY --from=builder /app/out .

# Expose port
EXPOSE 8080

# Run the server (chiseled images run as non-root by default)
ENTRYPOINT ["dotnet", "DiscordWebhook.dll"]

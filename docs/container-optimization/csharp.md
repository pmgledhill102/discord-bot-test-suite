# C# Container Optimization

## Services

| Service              | Current Base             | Current Size | Cold Start | Target Base | Target Size |
| -------------------- | ------------------------ | ------------ | ---------- | ----------- | ----------- |
| csharp-aspnet        | aspnet:10.0-alpine       | 57 MB        | 2.14s      | chiseled    | TBD         |
| csharp-aspnet-native | runtime-deps:10.0-alpine | 10 MB        | 409ms      | chiseled    | TBD         |

## Current State

- csharp-aspnet: Using aspnet:alpine, 2.14s cold start
- csharp-aspnet-native: Using native AOT, 409ms cold start (fastest!)

## Optimization Tasks

### 1. Switch to Microsoft Chiseled Images

- [ ] csharp-aspnet: `mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled`
- [ ] csharp-aspnet-native: `mcr.microsoft.com/dotnet/runtime-deps:10.0-noble-chiseled`

**Implementation:**

```dockerfile
# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled
WORKDIR /app
COPY --from=builder /app/out .
ENTRYPOINT ["dotnet", "DiscordWebhook.dll"]
```

### 2. Enable ReadyToRun (R2R) for csharp-aspnet

- [ ] Add `-p:PublishReadyToRun=true` to dotnet publish

**Implementation:**

```dockerfile
RUN dotnet publish -c Release -o out -p:PublishReadyToRun=true
```

### 3. Investigation: Assembly Trimming

- [ ] Research `-p:PublishTrimmed=true`
- [ ] May require annotations for reflection usage

### 4. Runtime Configuration

- [ ] Add `ENV MALLOC_ARENA_MAX=2` to both services

## Progress Log

### 2026-01-23 - Baseline

- csharp-aspnet: 57 MB, 2.14s cold start
- csharp-aspnet-native: 10 MB, 409ms cold start (best cold start!)
- Native AOT already well optimized

## Files to Modify

- `services/csharp-aspnet/Dockerfile`
- `services/csharp-aspnet-native/Dockerfile`

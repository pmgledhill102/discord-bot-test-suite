# Build stage
FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine AS builder

WORKDIR /app

# Copy project file first for better layer caching
COPY *.csproj ./
RUN dotnet restore

# Copy source code
COPY . .

# Build the application
RUN dotnet publish -c Release -o out

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:10.0-alpine

WORKDIR /app

# Copy the published output
COPY --from=builder /app/out .

# Expose port
EXPOSE 8080

# Run the server
ENTRYPOINT ["dotnet", "DiscordWebhook.dll"]

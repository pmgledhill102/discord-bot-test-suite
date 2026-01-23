# Build stage
FROM node:24-alpine AS builder

WORKDIR /app

# Copy package files first for better layer caching
COPY package.json ./
RUN npm install --omit=dev

# Copy source code
COPY src ./src

# Runtime stage - distroless for smaller image and better security
FROM gcr.io/distroless/nodejs24-debian12

WORKDIR /app

# Optimize memory allocation for containerized Node.js
ENV MALLOC_ARENA_MAX=2

# Copy node_modules and source from builder
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/src ./src
COPY --from=builder /app/package.json ./

# Expose port
EXPOSE 8080

# Run the server (exec form required - no shell in distroless)
CMD ["src/index.js"]

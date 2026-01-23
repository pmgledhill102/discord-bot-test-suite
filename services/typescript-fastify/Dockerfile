# Build stage
FROM node:22-alpine AS builder

WORKDIR /app

# Copy package files first for better layer caching
COPY package.json package-lock.json* ./
RUN npm ci

# Copy source code
COPY tsconfig.json ./
COPY src ./src

# Build TypeScript
RUN npm run build

# Install production dependencies only
RUN rm -rf node_modules && npm ci --omit=dev

# Runtime stage - distroless for smaller image and better security
FROM gcr.io/distroless/nodejs22-debian12

WORKDIR /app

# Optimize memory allocation for containerized Node.js
ENV MALLOC_ARENA_MAX=2

# Copy node_modules from builder (production deps only)
COPY --from=builder /app/node_modules ./node_modules

# Copy built application
COPY --from=builder /app/dist ./dist

# Expose port
EXPOSE 8080

# Run the server (exec form required - no shell in distroless)
CMD ["dist/index.js"]

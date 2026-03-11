
FROM node:22-alpine AS deps

# Install system packages needed to compile native add-ons (pg, etc.)
RUN apk add --no-cache python3 make g++

WORKDIR /build

# Copy manifests first – maximises layer caching
COPY package*.json ./

# Install ALL deps (including devDeps) so tests can run in CI if needed
RUN npm ci --prefer-offline



FROM node:22-alpine AS prod-deps

WORKDIR /build
COPY package*.json ./
COPY --from=deps /build/node_modules ./node_modules

# Prune dev-only packages to keep the final image lean
RUN npm prune --production



FROM node:22-alpine AS runtime


RUN apk add --no-cache dumb-init && \
    mkdir -p /app && \
    chown -R node:node /app

WORKDIR /app

# Copy pruned production node_modules from previous stage
COPY --from=prod-deps --chown=node:node /build/node_modules ./node_modules

# Copy application source
COPY --chown=node:node package*.json ./
COPY --chown=node:node src/           ./src/

# Switch to non-root user
USER node

# Application port
EXPOSE 3000

# Environment defaults (overridden at runtime via docker-compose / K8s)
ENV NODE_ENV=production \
    PORT=3000

# Liveness / readiness probe understood by Docker and most orchestrators
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

# Use dumb-init to properly handle PID 1 signal forwarding
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "src/app.js"]
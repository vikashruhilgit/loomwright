---
name: docker
description: Docker best practices for containerized applications. Covers multi-stage builds, docker-compose, health checks, .dockerignore, and image optimization. Use when containerizing services.
allowed-tools: [Read, Bash]
version: "1.0.0"
lastUpdated: "2026-03"
---

# Docker

Patterns for building efficient, secure Docker images and compose configurations.

---

## When to Use

- Containerizing a new application or service
- Optimizing existing Docker builds for size and speed
- Setting up local development with docker-compose
- Reviewing Dockerfiles for security and best practices

## When NOT to Use

- CI/CD pipeline configuration — use the `ci-cd` skill (loomwright@atelier plugin)
- Kubernetes orchestration — separate concern
- Cloud provider-specific container services (ECS, Cloud Run) — separate concern

## Core Patterns

### 1. Multi-Stage Build (Node.js)

```dockerfile
# Stage 1: Install dependencies
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts

# Stage 2: Build
FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

# Stage 3: Production
FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production

RUN addgroup --system --gid 1001 appgroup && \
    adduser --system --uid 1001 appuser

COPY --from=builder --chown=appuser:appgroup /app/dist ./dist
COPY --from=builder --chown=appuser:appgroup /app/node_modules ./node_modules
COPY --from=builder --chown=appuser:appgroup /app/package.json ./

USER appuser
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

CMD ["node", "dist/main.js"]
```

### 2. Dockerignore

```
# .dockerignore
node_modules
dist
.git
.github
.env*
*.md
coverage
test
.supervisor
.beads
```

### 3. Docker Compose for Development

```yaml
# docker-compose.yml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
      target: deps  # Use deps stage for dev
    volumes:
      - .:/app
      - /app/node_modules  # Prevent host node_modules from overriding
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=development
      - DATABASE_URL=mysql://root:secret@db:3306/app
    depends_on:
      db:
        condition: service_healthy

  db:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: secret
      MYSQL_DATABASE: app
    ports:
      - "3306:3306"
    volumes:
      - db_data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s

volumes:
  db_data:
```

### 4. Health Check Patterns

Always include health checks for orchestrator visibility:

```dockerfile
# HTTP health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# TCP health check (for non-HTTP services)
HEALTHCHECK --interval=30s --timeout=3s \
  CMD nc -z localhost 5432 || exit 1
```

### 5. Image Optimization

- Use `alpine` base images when possible (5x smaller)
- Install only production dependencies in final stage
- Order layers by change frequency (package.json before source code)
- Use `.dockerignore` to exclude build artifacts and dev files
- Pin image versions: `node:20.11-alpine` not `node:latest`

## Example Implementation

A minimal NestJS Dockerfile applying multi-stage build, non-root user, and health check patterns:

```dockerfile
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts

FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build && npm prune --production

FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup -S app && adduser -S app -G app
COPY --from=builder --chown=app:app /app/dist ./dist
COPY --from=builder --chown=app:app /app/node_modules ./node_modules
COPY --from=builder --chown=app:app /app/package.json ./
USER app
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1
CMD ["node", "dist/main.js"]
```

## Testing Approach

- Build the image and verify final size is under 200MB with `docker image inspect --format='{{.Size}}'`
- Run `docker compose up` and confirm all `depends_on` health checks pass before the app container starts
- Verify the container runs as non-root: `docker exec <container> whoami` should not return `root`
- Test the health check endpoint responds correctly: `docker inspect --format='{{.State.Health.Status}}' <container>`

## Anti-Patterns

- **Running as root:** Always create and switch to a non-root user.
- **Using `latest` tag:** Pin versions for reproducible builds.
- **Copying everything first:** Copy package.json separately to leverage layer caching.
- **No `.dockerignore`:** Without it, `.git`, `node_modules`, and secrets get sent to the build context.
- **Single-stage builds:** Production images should not contain build tools, dev dependencies, or source code.
- **No health check:** Orchestrators cannot determine container readiness without health checks.

## Related Skills

- `ci-cd` (loomwright@atelier plugin) — Building and pushing images in CI pipelines
- `monitoring-observability` (loomwright@atelier plugin) — Container logging and metrics
- `mysql` — Database container setup
- `redis-caching` — Redis container configuration

## Quality Gates

- [ ] Multi-stage build separates deps, build, and runtime
- [ ] Final stage runs as non-root user
- [ ] `.dockerignore` excludes `.git`, `node_modules`, `.env*`, test files
- [ ] Base image versions are pinned (no `latest`)
- [ ] Health check defined with appropriate interval and start period
- [ ] No secrets baked into the image (use runtime env vars)
- [ ] Image size is reasonable (< 200MB for Node.js apps)
- [ ] `docker-compose` services declare `depends_on` with health conditions

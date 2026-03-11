# 🚀 DevOps Pipeline — Node.js Web Application

A production-ready Node.js application with a complete DevOps pipeline covering containerisation, CI/CD, security scanning, and zero-downtime deployments.

---

## Architecture

```
Internet → Nginx (port 80) → Node.js App (port 3000) → PostgreSQL
                                                       → Redis
```

| Service  | Image               | Purpose                     |
|----------|---------------------|-----------------------------|
| app      | node:20-alpine      | Express API                 |
| postgres | postgres:16-alpine  | Persistent storage          |
| redis    | redis:7-alpine      | Cache & session store       |


---

## Part 1 — Containerisation

### Quick Start

```bash
# 1. Clone and configure
First create a docker network with this command
docker network create swiftride-net
# Edit .env with strong passwords

# 2. Start the full stack
docker compose up -d

# 3. Verify
curl http://localhost/health
curl http://localhost/status
curl -X POST http://localhost/process \
  -H "Content-Type: application/json" \
  -d '{"data": {"action": "hello", "value": 42}}'
```

### Dockerfile highlights

| Practice              | Detail                                              |
|-----------------------|-----------------------------------------------------|
| Multi-stage build     | `deps` → `prod-deps` → `runtime` (3 stages)        |
| Non-root user         | Runs as `node` (uid 1000)                           |
| Minimal base image    | `node:20-alpine` (~50 MB)                           |
| Signal handling       | `dumb-init` as PID 1                               |
| Read-only filesystem  | `read_only: true` + `tmpfs: /tmp`                  |
| Health check          | `wget` liveness probe every 30 s                   |
| Layer caching         | `package.json` copied before source                |

### Environment Variables

 `.env` and set all values before running.

| Variable           | Default        | Description              |
|--------------------|----------------|--------------------------|
| `NODE_ENV`         | `production`   | Runtime environment      |
| `PORT`             | `3000`         | App listen port          |
| `POSTGRES_DB`      | `appdb`        | Database name            |
| `POSTGRES_USER`    | `appuser`      | DB username              |
| `POSTGRES_PASSWORD`| **required**   | DB password              |
| `REDIS_PASSWORD`   | **required**   | Redis AUTH password      |

---

## API Endpoints

### `GET /health`
Liveness probe — always returns 200 if the process is running.
```json
{ "status": "ok", "timestamp": "2024-01-15T10:30:00.000Z" }
```

### `GET /status`
Readiness probe — checks Postgres and Redis connectivity.
```json
{
  "status": "ready",
  "checks": { "postgres": true, "redis": true },
  "uptime": 3600,
  "memoryMB": 45,
  "version": "1.0.0"
}
```

### `POST /process`
Process a job — persists to Postgres and caches in Redis (TTL 5 min).

**Request:**
```json
{ "data": { "action": "example", "value": 42 } }
```
**Response (202):**
```json
{
  "jobId": "job-1705312200000-abc123",
  "input": { "action": "example", "value": 42 },
  "processed": true,
  "processedAt": "2024-01-15T10:30:00.000Z"
}
```

---

## Part 2 — CI/CD Pipeline (GitHub Actions)

```
Push / PR
   │
   ├─▶ [lint]  ESLint code quality gate
   │
   ├─▶ [test]  Jest tests (Postgres + Redis service containers)
   │            └─ Coverage report artifact
   │
   ├─▶ [build] Multi-arch Docker image (amd64 + arm64)
   │            └─ Trivy CVE scan → GitHub Security tab
   │
   ├─▶ [deploy-staging]   (develop branch only) SSH deploy
   │
   └─▶ [deploy-production] (main branch only)  Rolling restart
```

### Required GitHub Secrets

| Secret           | Purpose                      |
|------------------|------------------------------|
| `STAGING_HOST`   | Staging server IP / hostname |
| `STAGING_USER`   | SSH username                 |
| `STAGING_SSH_KEY`| Private SSH key              |
| `PROD_HOST`      | Production server hostname   |
| `PROD_USER`      | SSH username                 |
| `PROD_SSH_KEY`   | Private SSH key              |

`GITHUB_TOKEN` is provided automatically by GitHub Actions.

---

## Running Tests Locally

```bash
# Start dependency services
docker compose up -d postgres redis

# Install deps
npm ci

# Initialise test DB
PGPASSWORD=changeme psql -h localhost -U appuser -d appdb -f init.sql

# Run tests with coverage
npm test
```

---

## Project Structure

```
.
├── src/
│   └── app.js                   # Express application
├── app/
│   └── app.test.js              # Jest integration tests
├── .github/
│   └── workflows/
│       └── ci-cd.yml            # GitHub Actions pipeline
├── Dockerfile                   # Multi-stage container build
├── docker-compose.yml           # Local / staging stack
├── init.sql                     # Postgres schema bootstrap
├── package.json
├── .env.example                 # Environment variable template
├── .dockerignore
└── .gitignore
```

---

## Security Checklist

- Non-root container user
-  Read-only root filesystem
-  `no-new-privileges` security option
- Resource limits (CPU + memory) on all services
- Secrets via environment variables (never baked into image)
- Security headers (X-Frame-Options, CSP, etc.)
- Trivy CVE scan blocks on CRITICAL/HIGH
- `.dockerignore` excludes `.env`, tests, and dev files
- Postgres initialised with least-privilege `readonly` role

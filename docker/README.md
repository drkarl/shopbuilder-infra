# ShopBuilder Docker Compose Configuration

Docker Compose configuration for the ShopBuilder core runtime stack running on VPS.

## Services

| Service | Description | Ports |
|---------|-------------|-------|
| `frontend` | Node.js frontend served by Nginx | 3000 |
| `spring-api` | Main Spring Boot API server | 8080 |
| `spring-workers` | Background job processing (image processing, async tasks) | 8081 (internal health check only) |
| `rabbitmq` | Message broker for async communication | 5672, 15672 (management UI) |

### External Dependencies

This Docker Compose stack assumes a **PostgreSQL database is managed externally** (e.g., cloud-managed database like AWS RDS, or a separate server). The database is not included in this compose file. Ensure your database is accessible from the Docker host before starting services.

## Quick Start

1. Copy the environment file:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` with your configuration values.

3. Start all services:
   ```bash
   docker compose up -d
   ```

4. Check service status:
   ```bash
   docker compose ps
   ```

5. View logs:
   ```bash
   docker compose logs -f
   ```

## Configuration

### Environment Variables

All configuration is done through environment variables. See `.env.example` for all available options.

#### Required Variables

- `SPRING_DATASOURCE_URL` - PostgreSQL connection URL
- `SPRING_DATASOURCE_USERNAME` - Database username
- `SPRING_DATASOURCE_PASSWORD` - Database password
- `RABBITMQ_PASSWORD` - RabbitMQ password
- `JWT_SECRET` - JWT signing secret
- `AWS_ACCESS_KEY_ID` - AWS access key for S3
- `AWS_SECRET_ACCESS_KEY` - AWS secret key for S3
- `S3_BUCKET_NAME` - S3 bucket for asset storage

### Resource Limits

Default resource limits are configured for a medium-sized VPS. Adjust these in your `.env` file:

| Service | CPU Limit | Memory Limit |
|---------|-----------|--------------|
| frontend | 0.5 | 256MB |
| spring-api | 2.0 | 2GB |
| spring-workers | 2.0 | 2GB |
| rabbitmq | 1.0 | 512MB |

### Health Checks

All services have health checks configured:

- **frontend**: HTTP check on `/health` (port 80 internal, exposed on 3000)
- **spring-api**: HTTP check on `/actuator/health` (port 8080, externally accessible)
- **spring-workers**: HTTP check on `/actuator/health` (port 8081, internal only - not exposed to host)
- **rabbitmq**: `rabbitmq-diagnostics ping`

Health checks run every 30 seconds with a 10-second timeout and 3 retries.

> **Note**: The Spring service health checks use `curl`. Ensure your Spring Boot Docker images have `curl` installed, or modify the health checks to use an alternative like `wget --spider`.

> **Note**: Worker health checks are only accessible within the Docker network. For external monitoring, use `docker compose ps` or access worker health via `docker compose exec spring-workers curl http://localhost:8081/actuator/health`.

## Frontend Build Process

The frontend service uses a multi-stage Docker build. The Dockerfile and Nginx configuration are located in the `frontend/` directory.

### Building the Frontend Image

Build the frontend Docker image with environment variables passed as build arguments:

```bash
cd frontend
docker build \
  --build-arg VITE_API_URL=https://api.example.com \
  --build-arg VITE_SUPABASE_URL=https://xxx.supabase.co \
  --build-arg VITE_SUPABASE_ANON_KEY=your-anon-key \
  -t shopbuilder/frontend:latest \
  .
```

### Build Stages

1. **Build Stage** (`node:20-alpine`):
   - Installs npm dependencies
   - Builds the application with Vite (production mode)
   - Enables tree-shaking and minification

2. **Runtime Stage** (`nginx:1.27-alpine`):
   - Serves static files with Nginx
   - Includes SPA routing (fallback to index.html)
   - Gzip compression enabled
   - Static asset caching with immutable headers
   - Security headers configured

### Nginx Configuration Features

- **SPA Routing**: All routes fall back to `index.html`
- **Gzip Compression**: Enabled for text, CSS, JS, JSON, XML, and SVG
- **Static Asset Caching**: 1-year cache with `immutable` flag for hashed assets (JS, CSS, images, fonts)
- **Security Headers**: X-Frame-Options, X-Content-Type-Options, X-XSS-Protection, Referrer-Policy
- **Health Endpoint**: `/health` returns 200 OK for container health checks

### Environment Variables at Build Time

These variables are embedded in the built JavaScript bundle:

| Variable | Description |
|----------|-------------|
| `VITE_API_URL` | Backend API base URL |
| `VITE_SUPABASE_URL` | Supabase project URL |
| `VITE_SUPABASE_ANON_KEY` | Supabase anonymous key |

> **Note**: Since these are build-time variables, changing them requires rebuilding the Docker image.

## Operations

### Starting Services

```bash
# Start all services
docker compose up -d

# Start specific service
docker compose up -d spring-api
```

### Stopping Services

```bash
# Stop all services
docker compose down

# Stop and remove volumes (WARNING: data loss)
docker compose down -v
```

### Viewing Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f spring-api

# Last 100 lines
docker compose logs --tail=100 spring-api
```

### Scaling Workers

```bash
# Scale workers (if needed)
docker compose up -d --scale spring-workers=2
```

### Updating Services

```bash
# Pull latest images
docker compose pull

# Recreate containers with new images
docker compose up -d --force-recreate
```

## Volumes

| Volume | Purpose |
|--------|---------|
| `shopbuilder-rabbitmq-data` | RabbitMQ message persistence |
| `shopbuilder-worker-temp` | Temporary storage for image processing |

## Networking

All services communicate over the `shopbuilder-network` bridge network. Services can reach each other by service name:

- `rabbitmq` - RabbitMQ broker
- `frontend` - Frontend service (also available as `shopbuilder-frontend` container name)
- `spring-api` - API service (also available as `shopbuilder-api` container name)
- `spring-workers` - Worker service (service name, supports scaling)

## Production Considerations

### RabbitMQ Management UI

The RabbitMQ management UI is exposed on port 15672 by default. For production environments:

- **Restrict access**: Use a firewall to limit access to internal networks only
- **Disable if unused**: Remove the `15672:15672` port mapping if the management UI is not needed
- **Use a reverse proxy**: Place behind an authenticated reverse proxy for secure external access

### Image Pull Policy

For production deployments, consider how images should be pulled:

```yaml
# Always pull the latest image (ensures updates)
pull_policy: always

# Only pull if image is missing (deterministic deployments)
pull_policy: missing
```

Add `pull_policy` to service definitions in `docker-compose.yml` as needed.

## Troubleshooting

### Service won't start

1. Check logs: `docker compose logs <service-name>`
2. Verify environment variables in `.env`
3. Check health status: `docker compose ps`

### RabbitMQ connection issues

1. Ensure RabbitMQ is healthy: `docker compose exec rabbitmq rabbitmq-diagnostics status`
2. Check credentials in `.env` match across services

### Out of memory

1. Check resource usage: `docker stats`
2. Adjust memory limits in `.env`
3. Consider scaling horizontally

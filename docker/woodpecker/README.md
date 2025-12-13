# Woodpecker CI Configuration

Docker Compose configuration for Woodpecker CI server and build agents.

## Overview

This configuration deploys:

- **Woodpecker Server**: Web UI, API, and agent coordinator
- **Woodpecker Agent**: Build executor using Docker backend

## Prerequisites

- Docker Engine 20.10+
- Docker Compose v2.0+
- GitHub OAuth Application (for authentication)

### Creating a GitHub OAuth App

1. Go to [GitHub Developer Settings](https://github.com/settings/developers)
2. Click "New OAuth App"
3. Fill in the details:
   - **Application name**: `Woodpecker CI`
   - **Homepage URL**: Your Woodpecker server URL (e.g., `https://ci.example.com`)
   - **Authorization callback URL**: `https://ci.example.com/authorize`
4. Note the Client ID and generate a Client Secret

## Quick Start

1. Copy the environment file:

   ```bash
   cp .env.example .env
   ```

2. Generate an agent secret:

   ```bash
   openssl rand -hex 32
   ```

3. Edit `.env` with your configuration:

   ```bash
   WOODPECKER_HOST=https://ci.example.com
   WOODPECKER_AGENT_SECRET=<generated-secret>
   WOODPECKER_GITHUB_CLIENT=<github-oauth-client-id>
   WOODPECKER_GITHUB_SECRET=<github-oauth-client-secret>
   WOODPECKER_ADMIN=your-github-username
   ```

4. Start the services:

   ```bash
   docker compose up -d
   ```

5. Access the UI at `http://localhost:8000` (or your configured domain)

## Configuration

### Required Environment Variables

| Variable | Description |
|----------|-------------|
| `WOODPECKER_HOST` | Public URL where Woodpecker is accessible |
| `WOODPECKER_AGENT_SECRET` | Shared secret for agent authentication |
| `WOODPECKER_GITHUB_CLIENT` | GitHub OAuth App client ID |
| `WOODPECKER_GITHUB_SECRET` | GitHub OAuth App client secret |

### Optional Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `WOODPECKER_VERSION` | `2.7.0` | Docker image version (pin for reproducibility) |
| `WOODPECKER_OPEN` | `false` | Allow public registration |
| `WOODPECKER_ADMIN` | - | Comma-separated admin usernames |
| `WOODPECKER_LOG_LEVEL` | `info` | Logging verbosity |
| `WOODPECKER_MAX_WORKFLOWS` | `1` | Concurrent workflows per agent |

### Resource Limits

Default limits are configured for a medium-sized VPS:

| Service | CPU Limit | Memory Limit |
|---------|-----------|--------------|
| Server | 1.0 | 512MB |
| Agent | 2.0 | 4GB |

Adjust these in `.env` based on your workload.

## Agent Scaling

### Running Multiple Agents

To scale build capacity, run multiple agents. Each agent can handle concurrent workflows.

#### Option 1: Docker Compose Scale

Scale agents dynamically:

```bash
# Start with 3 agents
docker compose up -d --scale woodpecker-agent=3
```

#### Option 2: Separate Agent Hosts

For distributed deployments, run agents on separate hosts:

1. Copy `docker-compose.agent.yml` (agent-only config):

   ```yaml
   services:
     woodpecker-agent:
       image: woodpeckerci/woodpecker-agent:${WOODPECKER_VERSION:-2.7.0}
       restart: unless-stopped
       environment:
         - WOODPECKER_SERVER=${WOODPECKER_SERVER_ADDRESS}:9000
         - WOODPECKER_AGENT_SECRET=${WOODPECKER_AGENT_SECRET}
         - WOODPECKER_HOSTNAME=${HOSTNAME:-agent}
         - WOODPECKER_MAX_WORKFLOWS=${WOODPECKER_MAX_WORKFLOWS:-2}
       volumes:
         - /var/run/docker.sock:/var/run/docker.sock
   ```

2. Configure each agent with a unique hostname:

   ```bash
   WOODPECKER_AGENT_HOSTNAME=agent-build-01
   WOODPECKER_SERVER_ADDRESS=ci.example.com
   ```

3. Start the agent:

   ```bash
   docker compose -f docker-compose.agent.yml up -d
   ```

### Agent Capacity Planning

| Workload | Agents | Max Workflows/Agent | Total Capacity |
|----------|--------|---------------------|----------------|
| Small team | 1 | 1 | 1 concurrent build |
| Medium team | 2 | 2 | 4 concurrent builds |
| Large team | 4+ | 2-4 | 8-16 concurrent builds |

**Recommendations:**
- Start with `WOODPECKER_MAX_WORKFLOWS=1` and increase based on agent resources
- Each workflow runs in its own Docker container
- Monitor agent memory usage during builds

## Database Configuration

### SQLite (Default)

Suitable for small deployments:

```bash
WOODPECKER_DATABASE_DRIVER=sqlite3
WOODPECKER_DATABASE_DATASOURCE=/var/lib/woodpecker/woodpecker.sqlite
```

### PostgreSQL (Production)

Recommended for production:

```bash
WOODPECKER_DATABASE_DRIVER=postgres
WOODPECKER_DATABASE_DATASOURCE=postgres://user:password@host:5432/woodpecker?sslmode=require  # pragma: allowlist secret
```

## Health Checks

Both services include health checks:

| Service | Endpoint | Interval |
|---------|----------|----------|
| Server | `http://localhost:8000/healthz` | 30s |
| Agent | `http://localhost:3000/healthz` | 30s |

Check service health:

```bash
docker compose ps
docker compose exec woodpecker-server wget -q --spider http://localhost:8000/healthz && echo "OK"
```

## Operations

### Viewing Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f woodpecker-server
docker compose logs -f woodpecker-agent
```

### Updating Woodpecker

```bash
# Pin to a specific version in .env
WOODPECKER_VERSION=2.7.0

# Pull and restart
docker compose pull
docker compose up -d
```

### Backup

For SQLite, backup the data volume:

```bash
docker compose stop woodpecker-server
docker cp $(docker compose ps -q woodpecker-server):/var/lib/woodpecker/woodpecker.sqlite ./backup/
docker compose start woodpecker-server
```

## Network Configuration

### Internal Network

Services communicate over the `woodpecker-network` bridge:

- Agents connect to server on port 9000 (gRPC)
- Server manages agents and distributes builds

### External Access

Configure a reverse proxy (Traefik, nginx, Caddy) for production:

```nginx
server {
    listen 443 ssl http2;
    server_name ci.example.com;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Firewall Rules

Required ports:

| Port | Protocol | Direction | Purpose |
|------|----------|-----------|---------|
| 8000 | TCP | Inbound | Web UI and API |
| 9000 | TCP | Internal/Inbound | Agent gRPC (see below) |

**gRPC Port (9000) Exposure:**
- **Same-host agents**: When agents run in the same Docker Compose stack, they connect via the internal `woodpecker-network` using service names (e.g., `woodpecker-server:9000`). External port exposure is not required.
- **Distributed agents**: When running agents on separate hosts, expose port 9000 to allow remote agents to connect. In this case, ensure the port is protected by firewall rules or VPN.

## Monitoring

### Agent Status

View connected agents in the Woodpecker UI under Settings > Agents.

### Metrics

Woodpecker exposes Prometheus metrics:

- Server: `http://localhost:8000/metrics`

### Docker Stats

Monitor resource usage:

```bash
# For single agent setup
docker stats woodpecker-server woodpecker-agent

# For scaled agents (shows all containers in the stack)
docker stats $(docker compose ps -q)
```

## Troubleshooting

### Agent Not Connecting

1. Verify the agent secret matches:

   ```bash
   docker compose exec woodpecker-agent env | grep WOODPECKER_AGENT_SECRET
   docker compose exec woodpecker-server env | grep WOODPECKER_AGENT_SECRET
   ```

2. Check network connectivity:

   ```bash
   docker compose exec woodpecker-agent wget -q --spider woodpecker-server:9000 && echo "OK"
   ```

3. Check agent logs:

   ```bash
   docker compose logs woodpecker-agent
   ```

### Builds Failing

1. Check agent has Docker access:

   ```bash
   docker compose exec woodpecker-agent docker ps
   ```

2. Ensure Docker socket is mounted:

   ```bash
   docker compose exec woodpecker-agent ls -la /var/run/docker.sock
   ```

### Server Not Starting

1. Check required environment variables:

   ```bash
   docker compose config | grep -E "(WOODPECKER_HOST|WOODPECKER_AGENT_SECRET|WOODPECKER_GITHUB)"
   ```

2. Verify database permissions:

   ```bash
   docker compose exec woodpecker-server ls -la /var/lib/woodpecker/
   ```

## Security Considerations

### Docker Socket Access

The agent mounts `/var/run/docker.sock`, giving it root-equivalent access to the host. Mitigations:

- Run agents on dedicated build hosts
- Use rootless Docker where possible
- Consider using Podman backend instead

### Secrets Management

For production, use SOPS to manage secrets:

```bash
# Decrypt and run
sops exec-env ../../secrets/production.enc.yaml 'docker compose up -d'
```

See `docs/secrets-management.md` for details.

### Network Isolation

- Keep gRPC port (9000) internal only
- Use TLS for external web access
- Restrict management access to trusted networks

# Woodpecker CI Server

This document describes the setup and configuration of the Woodpecker CI server for ShopBuilder infrastructure.

## Overview

[Woodpecker CI](https://woodpecker-ci.org/) is a community-driven fork of Drone CI, providing continuous integration and delivery. The server is accessible at `https://ci.staticshop.io`.

## Architecture

```
┌─────────────────────┐     ┌─────────────────────┐
│   GitHub.com        │────▶│ Woodpecker Server   │
│   (OAuth + Webhooks)│     │ (ci.staticshop.io)  │
└─────────────────────┘     └──────────┬──────────┘
                                       │
                                       ▼
                            ┌─────────────────────┐
                            │  Woodpecker Agent   │
                            │  (Docker executor)  │
                            └─────────────────────┘
```

Components:
- **Woodpecker Server**: Web UI and API, handles GitHub webhooks and OAuth
- **Woodpecker Agent**: Executes pipeline steps in Docker containers
- **Cloudflare**: Provides SSL termination, DDoS protection, and reverse proxy

## Prerequisites

1. **VPS Instance**: A server with Docker installed (use the `vps` Terraform module)
2. **GitHub OAuth App**: For user authentication
3. **Cloudflare DNS**: DNS record pointing to the server

## GitHub OAuth Setup

1. Create a GitHub OAuth App at https://github.com/settings/developers
2. Configure the application:
   - **Application name**: `ShopBuilder CI`
   - **Homepage URL**: `https://ci.staticshop.io`
   - **Authorization callback URL**: `https://ci.staticshop.io/authorize`
3. Store the Client ID and Secret in SOPS-encrypted secrets

## Deployment

### 1. Provision VPS

First, ensure a VPS is provisioned using the Terraform `vps` module. The VPS should have:
- Docker and Docker Compose installed
- Firewall allowing ports 80/443 from Cloudflare IPs only

### 2. Configure DNS

The DNS record is configured in `terraform/environments/prod/main.tf`:

```hcl
# In the dns module custom_records:
{
  name    = "ci"
  value   = var.woodpecker_server_ip
  type    = "A"
  proxied = true
  comment = "Woodpecker CI server"
}
```

Set the `woodpecker_server_ip` variable in your terraform.tfvars or environment.

### 3. Configure Secrets

Add the following to your SOPS-encrypted secrets file:

```yaml
WOODPECKER_GITHUB_CLIENT: <github-oauth-client-id>
WOODPECKER_GITHUB_SECRET: <github-oauth-client-secret>
WOODPECKER_AGENT_SECRET: <generate-with-openssl-rand-hex-32>
```

Generate the agent secret:
```bash
openssl rand -hex 32
```

### 4. Create Environment File

On the VPS, create `/opt/woodpecker/.env`:

```bash
# Server configuration
WOODPECKER_HOST=https://ci.staticshop.io
WOODPECKER_ADMIN=<github-username>

# GitHub OAuth (from SOPS secrets)
WOODPECKER_GITHUB_CLIENT=<from-secrets>
WOODPECKER_GITHUB_SECRET=<from-secrets>
WOODPECKER_AGENT_SECRET=<from-secrets>
```

### 5. Deploy with Docker Compose

```bash
# Copy the compose file to the server
scp docker/docker-compose.woodpecker.yml root@<server-ip>:/opt/woodpecker/

# SSH to the server
ssh root@<server-ip>

# Start the services
cd /opt/woodpecker
docker compose -f docker-compose.woodpecker.yml up -d

# Verify services are running
docker compose -f docker-compose.woodpecker.yml ps
```

## Configuration Options

### Server Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `WOODPECKER_HOST` | Public URL of the server | Required |
| `WOODPECKER_ADMIN` | Comma-separated list of admin GitHub usernames | Required |
| `WOODPECKER_OPEN` | Allow open registration | `false` |
| `WOODPECKER_GITHUB` | Enable GitHub authentication | `true` |
| `WOODPECKER_GITHUB_CLIENT` | GitHub OAuth Client ID | Required |
| `WOODPECKER_GITHUB_SECRET` | GitHub OAuth Client Secret | Required |
| `WOODPECKER_AGENT_SECRET` | Shared secret for agent authentication | Required |
| `WOODPECKER_DATABASE_DRIVER` | Database driver | `sqlite3` |
| `WOODPECKER_LOG_LEVEL` | Log level (debug, info, warn, error) | `info` |

### Agent Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `WOODPECKER_SERVER` | Server gRPC address | Required |
| `WOODPECKER_AGENT_SECRET` | Shared secret (must match server) | Required |
| `WOODPECKER_MAX_WORKFLOWS` | Max concurrent workflows | `2` |

### Resource Limits

Default resource limits are set in the Docker Compose file:

| Service | CPU Limit | Memory Limit |
|---------|-----------|--------------|
| Server | 1.0 | 512M |
| Agent | 2.0 | 1G |

Override these via environment variables:
- `WOODPECKER_SERVER_CPU_LIMIT`
- `WOODPECKER_SERVER_MEMORY_LIMIT`
- `WOODPECKER_AGENT_CPU_LIMIT`
- `WOODPECKER_AGENT_MEMORY_LIMIT`

## Database Backup

The Woodpecker server uses SQLite by default. The database is stored in the `woodpecker-data` Docker volume.

### Manual Backup

```bash
# Create backup directory
mkdir -p /opt/backups/woodpecker

# Backup the SQLite database
docker run --rm \
  -v woodpecker-data:/data:ro \
  -v /opt/backups/woodpecker:/backup \
  alpine cp /data/woodpecker.sqlite /backup/woodpecker-$(date +%Y%m%d_%H%M%S).sqlite
```

### Automated Backup (Cron)

Add to crontab (`crontab -e`):

```cron
# Daily backup at 2 AM
0 2 * * * docker run --rm -v woodpecker-data:/data:ro -v /opt/backups/woodpecker:/backup alpine cp /data/woodpecker.sqlite /backup/woodpecker-$(date +\%Y\%m\%d).sqlite

# Keep only last 7 days of backups
0 3 * * * find /opt/backups/woodpecker -name "*.sqlite" -mtime +7 -delete
```

### Restore from Backup

```bash
# Stop the server
docker compose -f docker-compose.woodpecker.yml stop woodpecker-server

# Restore the database
docker run --rm \
  -v woodpecker-data:/data \
  -v /opt/backups/woodpecker:/backup \
  alpine cp /backup/woodpecker-20240101.sqlite /data/woodpecker.sqlite

# Start the server
docker compose -f docker-compose.woodpecker.yml start woodpecker-server
```

## Monitoring

### Health Checks

The server exposes a health endpoint at `/healthz`:

```bash
curl https://ci.staticshop.io/healthz
```

### Logs

View logs with Docker Compose:

```bash
# All services
docker compose -f docker-compose.woodpecker.yml logs -f

# Server only
docker compose -f docker-compose.woodpecker.yml logs -f woodpecker-server

# Agent only
docker compose -f docker-compose.woodpecker.yml logs -f woodpecker-agent
```

## Troubleshooting

### OAuth Login Fails

1. Verify the callback URL matches exactly: `https://ci.staticshop.io/authorize`
2. Check that `WOODPECKER_HOST` is set correctly (include `https://`)
3. Verify GitHub OAuth credentials are correct

### Agent Not Connecting

1. Ensure `WOODPECKER_AGENT_SECRET` matches on both server and agent
2. Verify the agent can reach `woodpecker-server:9000`
3. Check agent logs for connection errors

### Pipelines Not Triggering

1. Verify GitHub webhooks are configured (check repository Settings > Webhooks)
2. Check that the repository is activated in Woodpecker UI
3. Verify `.woodpecker.yml` exists in the repository root

## Pipeline Configuration

Create `.woodpecker.yml` in your repository:

```yaml
steps:
  - name: build
    image: node:20
    commands:
      - npm ci
      - npm run build

  - name: test
    image: node:20
    commands:
      - npm test

  - name: deploy
    image: alpine
    secrets: [deploy_key]
    commands:
      - echo "Deploying..."
    when:
      branch: main
      event: push
```

## Security Considerations

1. **Network Isolation**: The server only accepts HTTP traffic from Cloudflare IPs
2. **Secrets Management**: All sensitive values are stored in SOPS-encrypted files
3. **Admin Access**: Limit `WOODPECKER_ADMIN` to trusted GitHub usernames
4. **Open Registration**: Keep `WOODPECKER_OPEN=false` to prevent unauthorized access
5. **Docker Socket**: The agent mounts the Docker socket; ensure the host is trusted

## Related Documentation

- [Woodpecker CI Documentation](https://woodpecker-ci.org/docs/intro)
- [Secrets Management](./secrets-management.md)
- [VPS Module](../terraform/modules/vps/README.md)

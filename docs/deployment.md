# Deployment Guide

This guide covers deploying the ShopBuilder application stack to VPS using Docker Compose with SOPS-encrypted secrets.

## Prerequisites

### Local Machine (Operator)

1. **SOPS** - for decrypting secrets
   ```bash
   # macOS
   brew install sops

   # Linux
   curl -LO https://github.com/getsops/sops/releases/download/v3.9.0/sops-v3.9.0.linux.amd64
   chmod +x sops-v3.9.0.linux.amd64
   sudo mv sops-v3.9.0.linux.amd64 /usr/local/bin/sops
   ```

2. **age** - encryption backend (for key generation)
   ```bash
   # macOS
   brew install age

   # Linux
   curl -LO https://github.com/FiloSottile/age/releases/download/v1.2.0/age-v1.2.0-linux-amd64.tar.gz
   tar -xzf age-v1.2.0-linux-amd64.tar.gz
   sudo mv age/age age/age-keygen /usr/local/bin/
   ```

3. **SSH access** to the target VPS
4. **Age private key** for the target environment (stored in `keys/`)

### Target VPS

- Docker and Docker Compose installed
- SSH access configured
- Network access to container registries

## Security Model

The deployment scripts follow a secure-by-design approach:

1. **Age private keys never leave the operator's machine** - decryption happens locally
2. **Secrets are transferred encrypted** - only the decrypted `.env` file is transferred
3. **Plaintext secrets are immediately deleted** - using `shred` when available
4. **No secrets stored on VPS** - the `.env` file is deleted after Docker reads it

```
┌─────────────────────┐     ┌─────────────────────┐
│  Operator Machine   │     │      Target VPS     │
│                     │     │                     │
│  ┌───────────────┐  │     │  ┌───────────────┐  │
│  │ age key       │  │     │  │ Docker        │  │
│  │ (private)     │  │     │  │ Compose       │  │
│  └───────┬───────┘  │     │  └───────────────┘  │
│          │          │     │          ▲          │
│          ▼          │     │          │          │
│  ┌───────────────┐  │     │  ┌───────────────┐  │
│  │ SOPS decrypt  │  │ SCP │  │ .env file     │  │
│  │ secrets.enc   │──┼─────┼─▶│ (temporary)   │  │
│  └───────────────┘  │     │  └───────┬───────┘  │
│                     │     │          │          │
│                     │     │          ▼          │
│                     │     │  ┌───────────────┐  │
│                     │     │  │ Containers    │  │
│                     │     │  │ start         │  │
│                     │     │  └───────────────┘  │
│                     │     │          │          │
│                     │     │          ▼          │
│                     │     │  ┌───────────────┐  │
│                     │     │  │ .env deleted  │  │
│                     │     │  │ (shred)       │  │
│                     │     │  └───────────────┘  │
└─────────────────────┘     └─────────────────────┘
```

## Quick Start

### Deploy to Staging

```bash
# Set VPS host (or use -h flag)
export VPS_HOST=staging.example.com

# Deploy
./scripts/deploy.sh staging
```

### Deploy to Production

```bash
# Deploy with specific version
./scripts/deploy.sh production -h prod.example.com -t v1.2.3
```

### Rollback

```bash
# List available versions
./scripts/rollback.sh production -h prod.example.com --list

# Rollback to specific version
./scripts/rollback.sh production -h prod.example.com v1.2.2
```

## Deployment Script Usage

### `scripts/deploy.sh`

```
Usage: ./scripts/deploy.sh <environment> [OPTIONS]

Arguments:
  environment         Target environment: staging or production

Options:
  -h, --host          VPS hostname or IP address (or set VPS_HOST)
  -u, --user          SSH user (default: root, or set VPS_USER)
  -p, --path          Remote deployment path (default: /opt/shop-builder)
  -k, --key           Age key file path (default: keys/<environment>.age.key)
  -t, --tag           Docker image tag to deploy (default: latest)
  --dry-run           Show what would be done without executing
  --skip-health       Skip health checks after deployment
  --help              Show help message
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `VPS_HOST` | Target VPS hostname or IP | (required) |
| `VPS_USER` | SSH username | `root` |
| `DEPLOY_PATH` | Remote deployment directory | `/opt/shop-builder` |
| `SOPS_AGE_KEY_FILE` | Path to age private key | `keys/<env>.age.key` |

### Examples

```bash
# Basic deployment
./scripts/deploy.sh staging -h staging.example.com

# Deploy specific version
./scripts/deploy.sh production -h prod.example.com -t v1.2.3

# Dry run (see what would happen)
./scripts/deploy.sh production -h prod.example.com --dry-run

# Skip health checks
./scripts/deploy.sh staging -h staging.example.com --skip-health

# Custom SSH user
./scripts/deploy.sh production -h prod.example.com -u deploy

# Using environment variables
export VPS_HOST=prod.example.com
export VPS_USER=deploy
./scripts/deploy.sh production -t v1.2.3
```

## Rollback Script Usage

### `scripts/rollback.sh`

```
Usage: ./scripts/rollback.sh <environment> [OPTIONS] [VERSION]

Arguments:
  environment         Target environment: staging or production
  VERSION             Docker image tag to rollback to

Options:
  -h, --host          VPS hostname or IP address (or set VPS_HOST)
  -u, --user          SSH user (default: root, or set VPS_USER)
  -p, --path          Remote deployment path (default: /opt/shop-builder)
  -k, --key           Age key file path (default: keys/<environment>.age.key)
  -l, --list          List available versions and deployment info
  -n, --count         Number of items to list (default: 10)
  --dry-run           Show what would be done without executing
  -y, --yes           Skip confirmation prompt
  --help              Show help message
```

### Examples

```bash
# List current deployment info and available versions
./scripts/rollback.sh production -h prod.example.com --list

# Rollback to specific version
./scripts/rollback.sh production -h prod.example.com v1.2.2

# Rollback without confirmation
./scripts/rollback.sh production -h prod.example.com -y v1.2.2

# Dry run
./scripts/rollback.sh production -h prod.example.com --dry-run v1.2.2
```

## Deployment Process

The deployment script performs these steps:

1. **Check requirements** - Verify SOPS, SSH, and required files exist
2. **Decrypt secrets** - Use age key to decrypt `secrets/<env>.enc.yaml` locally
3. **Transfer files** - SCP the `.env` and `docker-compose.yml` to VPS
4. **Deploy containers** - Run `docker compose pull && docker compose up -d`
5. **Clean up secrets** - Securely delete `.env` on both local and remote
6. **Health checks** - Verify all containers are running and healthy
7. **Save deployment info** - Record deployment metadata on VPS

## Health Checks

After deployment, the script verifies:

1. All containers are running (`docker compose ps`)
2. No containers are in `unhealthy` or `starting` state
3. Health check endpoints respond (as configured in docker-compose.yml)

Health check timeout: ~60 seconds (10 retries × 6 seconds)

### Manual Health Check Commands

```bash
# Check container status
ssh user@vps 'cd /opt/shop-builder && docker compose ps'

# View health check status
ssh user@vps 'cd /opt/shop-builder && docker inspect --format="{{.State.Health.Status}}" shopbuilder-api'

# Check logs for errors
ssh user@vps 'cd /opt/shop-builder && docker compose logs --tail=50'

# Test API health endpoint
ssh user@vps 'curl -f http://localhost:8080/actuator/health'
```

## Deployment Logs

Deployment logs are saved to `logs/deploy-<env>-<timestamp>.log`:

```bash
# View recent deployment logs
ls -la logs/

# Tail a deployment log
tail -f logs/deploy-production-20241201-143022.log
```

## Troubleshooting

### "Failed to decrypt secrets file"

1. Ensure your age private key matches the public key in `.sops.yaml`
2. Check the key file path: `keys/<environment>.age.key`
3. Verify `SOPS_AGE_KEY_FILE` environment variable if using custom path

```bash
# Verify key pair matches
age-keygen -y keys/production.age.key
# Should output the public key in .sops.yaml
```

### "Failed to connect to VPS"

1. Verify SSH access: `ssh user@vps-host`
2. Check SSH key is configured
3. Verify VPS is reachable and SSH port is open

### "Containers failed to start"

1. Check container logs: `docker compose logs`
2. Verify all required secrets are present
3. Check for port conflicts
4. Verify Docker images exist in registry

```bash
# SSH to VPS and debug
ssh user@vps
cd /opt/shop-builder
docker compose logs --tail=100
docker compose ps -a
```

### "Health checks did not pass"

1. Check container logs for startup errors
2. Verify database connectivity
3. Check for resource constraints (memory, CPU)
4. Increase health check timeout if services are slow to start

```bash
# Check individual container health
ssh user@vps 'docker inspect shopbuilder-api --format="{{json .State.Health}}" | jq'
```

## CI/CD Integration

### GitHub Actions

```yaml
name: Deploy

on:
  push:
    tags:
      - 'v*'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install SOPS
        run: |
          curl -LO https://github.com/getsops/sops/releases/download/v3.9.0/sops-v3.9.0.linux.amd64
          chmod +x sops-v3.9.0.linux.amd64
          sudo mv sops-v3.9.0.linux.amd64 /usr/local/bin/sops

      - name: Setup SSH
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.VPS_SSH_KEY }}" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519
          ssh-keyscan -H ${{ secrets.VPS_HOST }} >> ~/.ssh/known_hosts

      - name: Setup age key
        run: |
          mkdir -p keys
          echo "${{ secrets.SOPS_AGE_KEY }}" > keys/production.age.key

      - name: Deploy
        run: |
          ./scripts/deploy.sh production \
            -h ${{ secrets.VPS_HOST }} \
            -t ${{ github.ref_name }}
```

### Woodpecker CI

```yaml
steps:
  deploy:
    image: alpine
    secrets: [vps_ssh_key, vps_host, sops_age_key]
    commands:
      - apk add --no-cache openssh-client curl bash
      - curl -LO https://github.com/getsops/sops/releases/download/v3.9.0/sops-v3.9.0.linux.amd64
      - chmod +x sops-v3.9.0.linux.amd64 && mv sops-v3.9.0.linux.amd64 /usr/local/bin/sops
      - mkdir -p ~/.ssh keys
      - echo "$VPS_SSH_KEY" > ~/.ssh/id_ed25519 && chmod 600 ~/.ssh/id_ed25519
      - ssh-keyscan -H "$VPS_HOST" >> ~/.ssh/known_hosts
      - echo "$SOPS_AGE_KEY" > keys/production.age.key
      - ./scripts/deploy.sh production -h "$VPS_HOST" -t "${CI_COMMIT_TAG}"
    when:
      event: tag
```

## Best Practices

1. **Always use `--dry-run` first** when deploying to production
2. **Tag releases** with semantic versioning (v1.2.3) for easy rollbacks
3. **Test in staging** before deploying to production
4. **Monitor logs** after deployment for any issues
5. **Keep deployment logs** for audit purposes
6. **Rotate age keys** periodically (see `docs/secrets-management.md`)
7. **Back up age private keys** securely - loss means loss of access to secrets

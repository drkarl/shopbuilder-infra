# Woodpecker CI Secrets Configuration

This document describes how to configure and manage secrets for Woodpecker CI pipelines in the ShopBuilder infrastructure.

## Overview

Secrets in ShopBuilder follow a **dual storage** pattern:

1. **SOPS** (`secrets/*.enc.yaml`) - Single source of truth, version controlled
2. **Woodpecker** - Runtime secrets injected into CI/CD pipelines

This ensures secrets are both securely stored in version control and available at runtime.

## Required Secrets

| Secret Name | Description | Scope | Required |
|-------------|-------------|-------|----------|
| `cloudflare_api_token` | Cloudflare API access for DNS, Pages, R2 | Global | Yes |
| `cloudflare_account_id` | Cloudflare account identifier | Global | Yes |
| `shop_builder_api_token` | API callback authentication for build status | Repository | Yes |
| `docker_registry_token` | Private container registry access | Global | Optional |
| `sops_age_key` | Age private key for decrypting SOPS secrets | Global | Yes |

## Secret Scope

Woodpecker supports two secret scopes:

### Global Secrets (Organization-wide)

Global secrets are available to all repositories in the organization. Use for shared infrastructure credentials.

```bash
woodpecker-cli secret add \
  --global \
  --name cloudflare_api_token \
  --value "${CLOUDFLARE_API_TOKEN}"
```

### Repository Secrets (Per-repository)

Repository secrets are only available to a specific repository. Use for project-specific credentials.

```bash
woodpecker-cli secret add \
  --repository drkarl/shop-builder \
  --name shop_builder_api_token \
  --value "${SHOP_BUILDER_API_TOKEN}"
```

### Recommended Scope Configuration

| Secret | Recommended Scope | Reason |
|--------|-------------------|--------|
| `cloudflare_api_token` | Global | Shared across all deployment pipelines |
| `cloudflare_account_id` | Global | Shared across all deployment pipelines |
| `sops_age_key` | Global | Required by all pipelines that decrypt secrets |
| `shop_builder_api_token` | Repository | Specific to shop-builder project |
| `docker_registry_token` | Global | Shared if using single registry |

## Adding Secrets to Woodpecker

### Prerequisites

1. Install woodpecker-cli:
   ```bash
   # Download from releases
   curl -L https://github.com/woodpecker-ci/woodpecker/releases/latest/download/woodpecker-cli_linux_amd64.tar.gz | tar -xz
   sudo mv woodpecker-cli /usr/local/bin/
   ```

2. Configure CLI authentication:
   ```bash
   export WOODPECKER_SERVER=https://ci.example.com
   export WOODPECKER_TOKEN=your-personal-token
   ```

### Adding Secrets from SOPS

Use this workflow to sync secrets from SOPS to Woodpecker. Note that SOPS files use `SCREAMING_SNAKE_CASE` for variable names, while Woodpecker secret names use `lowercase_with_underscores`. Woodpecker automatically converts secret names to uppercase environment variables at runtime.

```bash
# 1. Decrypt SOPS secrets using yq (handles multi-line values safely)
export SOPS_AGE_KEY_FILE=keys/production.age.key
sops -d secrets/production.enc.yaml > /tmp/secrets.yaml

# 2. Extract individual secrets using yq
CLOUDFLARE_API_TOKEN=$(yq '.CLOUDFLARE_API_TOKEN' /tmp/secrets.yaml)
CLOUDFLARE_ACCOUNT_ID=$(yq '.CLOUDFLARE_ACCOUNT_ID' /tmp/secrets.yaml)
SHOP_BUILDER_API_TOKEN=$(yq '.SHOP_BUILDER_API_TOKEN' /tmp/secrets.yaml)

# 3. Add secrets to Woodpecker (global scope)
woodpecker-cli secret add --global --name cloudflare_api_token --value "${CLOUDFLARE_API_TOKEN}"
woodpecker-cli secret add --global --name cloudflare_account_id --value "${CLOUDFLARE_ACCOUNT_ID}"

# 4. Add repository-specific secrets
woodpecker-cli secret add --repository drkarl/shop-builder --name shop_builder_api_token --value "${SHOP_BUILDER_API_TOKEN}"

# 5. Clean up
rm -f /tmp/secrets.yaml
```

> **Note**: The `sops_age_key` secret requires special handling due to its multi-line format. See the "Individual Secret Commands" section below.

### Individual Secret Commands

```bash
# Cloudflare API Token
woodpecker-cli secret add \
  --global \
  --name cloudflare_api_token \
  --value "${CLOUDFLARE_API_TOKEN}"

# Cloudflare Account ID
woodpecker-cli secret add \
  --global \
  --name cloudflare_account_id \
  --value "${CLOUDFLARE_ACCOUNT_ID}"

# Shop Builder API Token
woodpecker-cli secret add \
  --repository drkarl/shop-builder \
  --name shop_builder_api_token \
  --value "${SHOP_BUILDER_API_TOKEN}"

# Docker Registry Token (optional)
woodpecker-cli secret add \
  --global \
  --name docker_registry_token \
  --value "${DOCKER_REGISTRY_TOKEN}"

# SOPS Age Key (for decrypting secrets in pipelines)
# Note: Read directly from the key file to preserve multi-line format
woodpecker-cli secret add \
  --global \
  --name sops_age_key \
  --value "$(cat keys/production.age.key)"
```

## Pipeline Usage

### Injecting Secrets

Reference secrets in your `.woodpecker.yml`:

```yaml
steps:
  deploy:
    image: alpine
    secrets: [cloudflare_api_token, cloudflare_account_id]
    commands:
      - echo "Deploying with Cloudflare..."
```

### Decrypting SOPS Secrets in Pipeline

For pipelines that need access to all SOPS secrets:

```yaml
steps:
  deploy:
    image: mozilla/sops:v3.9.0-alpine
    secrets: [sops_age_key]
    commands:
      # Create temporary key file and set up cleanup for both key and decrypted secrets
      - KEY_FILE=$(mktemp)
      - trap 'rm -f "$KEY_FILE" .env' EXIT
      - echo "$SOPS_AGE_KEY" > "$KEY_FILE"
      - export SOPS_AGE_KEY_FILE="$KEY_FILE"

      # Decrypt secrets
      - sops -d secrets/production.enc.yaml > .env

      # Use decrypted secrets
      - source .env
      - ./deploy.sh
```

### Complete Pipeline Example

```yaml
# .woodpecker.yml
variables:
  - &deploy_image alpine:3.19

steps:
  build:
    image: node:20-alpine
    commands:
      - npm ci
      - npm run build

  test:
    image: node:20-alpine
    commands:
      - npm run test

  deploy-staging:
    image: *deploy_image
    secrets: [cloudflare_api_token, cloudflare_account_id, shop_builder_api_token]
    commands:
      - apk add --no-cache curl
      - |
        # Deploy to Cloudflare Pages (--fail exits non-zero on HTTP errors)
        curl --fail -X POST "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects/shop-builder/deployments" \
          -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
          -F "branch=staging"
      - |
        # Notify Shop Builder API
        curl --fail -X POST "https://api.shop-builder.example/webhooks/deploy" \
          -H "Authorization: Bearer ${SHOP_BUILDER_API_TOKEN}" \
          -d '{"status": "deployed", "environment": "staging"}'
    when:
      branch: staging

  deploy-production:
    image: *deploy_image
    secrets: [cloudflare_api_token, cloudflare_account_id, shop_builder_api_token]
    commands:
      - apk add --no-cache curl
      - |
        # Deploy to Cloudflare Pages (--fail exits non-zero on HTTP errors)
        curl --fail -X POST "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects/shop-builder/deployments" \
          -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
          -F "branch=main"
      - |
        # Notify Shop Builder API
        curl --fail -X POST "https://api.shop-builder.example/webhooks/deploy" \
          -H "Authorization: Bearer ${SHOP_BUILDER_API_TOKEN}" \
          -d '{"status": "deployed", "environment": "production"}'
    when:
      branch: main
```

## Secret Rotation Checklist

When rotating secrets, follow this checklist to ensure no service disruption:

### Before Rotation

- [ ] Identify all services using the secret
- [ ] Verify new credentials work in a test environment
- [ ] Schedule rotation during low-traffic period

### Rotation Steps

1. **Update SOPS** (source of truth):
   ```bash
   export SOPS_AGE_KEY_FILE=keys/production.age.key
   sops secrets/production.enc.yaml
   # Edit the secret value, save and exit
   git add secrets/production.enc.yaml
   git commit -m "Rotate [secret_name]"
   git push
   ```

2. **Update Woodpecker**:
   ```bash
   # Update global secret
   woodpecker-cli secret update --global --name [secret_name] --value "${NEW_VALUE}"

   # Or update repository secret
   woodpecker-cli secret update --repository drkarl/shop-builder --name [secret_name] --value "${NEW_VALUE}"
   ```

3. **Verify** the new secret works:
   ```bash
   # Trigger a test pipeline
   woodpecker-cli pipeline start drkarl/shop-builder
   ```

### After Rotation

- [ ] Verify all pipelines pass with new credentials
- [ ] Revoke old credentials (if possible)
- [ ] Update rotation timestamp in documentation
- [ ] Notify team of completed rotation

### Rotation Schedule

| Secret | Rotation Frequency | Last Rotated |
|--------|-------------------|--------------|
| `cloudflare_api_token` | Annually or on compromise | TBD |
| `shop_builder_api_token` | Annually or on team change | TBD |
| `docker_registry_token` | Annually | TBD |
| `sops_age_key` | Annually or on team change | TBD |

## Listing and Managing Secrets

### List Secrets

```bash
# List global secrets
woodpecker-cli secret ls --global

# List repository secrets
woodpecker-cli secret ls --repository drkarl/shop-builder
```

### Update Secrets

```bash
# Update global secret
woodpecker-cli secret update --global --name cloudflare_api_token --value "${NEW_TOKEN}"

# Update repository secret
woodpecker-cli secret update --repository drkarl/shop-builder --name shop_builder_api_token --value "${NEW_TOKEN}"
```

### Remove Secrets

```bash
# Remove global secret
woodpecker-cli secret rm --global --name old_secret

# Remove repository secret
woodpecker-cli secret rm --repository drkarl/shop-builder --name old_secret
```

## Security Best Practices

1. **Principle of Least Privilege**: Only grant secrets the minimum scope needed
2. **Regular Rotation**: Rotate secrets according to the schedule above
3. **Audit Access**: Review who has access to Woodpecker admin and SOPS keys
4. **No Logging**: Ensure secrets are not logged in pipeline output
5. **Environment Isolation**: Use separate secrets for dev/staging/production
6. **Immediate Revocation**: Revoke compromised secrets immediately

## Troubleshooting

### Secret Not Available in Pipeline

1. Verify secret exists:
   ```bash
   woodpecker-cli secret ls --global
   woodpecker-cli secret ls --repository drkarl/shop-builder
   ```

2. Check secret name matches exactly (case-sensitive)

3. Ensure secret is listed in pipeline `secrets:` array

### Permission Denied

1. Verify WOODPECKER_TOKEN is valid
2. Check user has admin permissions for global secrets
3. Check user has write permissions for repository secrets

### SOPS Decryption Fails

1. Verify `sops_age_key` secret contains the correct private key
2. Check key file format (should start with `AGE-SECRET-KEY-`)
3. Verify the public key in `.sops.yaml` matches the private key

# Hugo Marketing Site Deployment

This document describes the deployment process for the Hugo marketing site to Cloudflare Pages.

## Overview

The marketing site (staticshop.io) is deployed to Cloudflare Pages using:

- **Terraform**: Infrastructure as Code for Pages project and DNS configuration
- **Wrangler CLI**: Direct Upload deployment from CI/CD or local
- **GitHub Actions**: Automated build and deployment pipeline

## Architecture

```
                    ┌─────────────────────────────────────────────────────┐
                    │                  Cloudflare Edge                    │
                    │  ┌──────────────────────────────────────────────┐  │
                    │  │              Cloudflare Pages                 │  │
   staticshop.io ──▶│  │     ┌───────────────────────────────┐       │  │
www.staticshop.io ─▶│  │     │    staticshop-marketing       │       │  │
                    │  │     │    (Hugo Static Site)         │       │  │
                    │  │     └───────────────────────────────┘       │  │
                    │  └──────────────────────────────────────────────┘  │
                    │                                                     │
                    │  ┌──────────────────────────────────────────────┐  │
                    │  │              Cloudflare DNS                   │  │
                    │  │  staticshop.io → CNAME → pages.dev           │  │
                    │  │  www.staticshop.io → CNAME → pages.dev       │  │
                    │  └──────────────────────────────────────────────┘  │
                    └─────────────────────────────────────────────────────┘
```

## Prerequisites

### Environment Variables

Set the following environment variables for deployment:

```bash
# Required for Terraform and Wrangler
export CLOUDFLARE_API_TOKEN="your-api-token"
export CLOUDFLARE_ACCOUNT_ID="your-32-char-hex-account-id"

# Required for Terraform only
export TF_VAR_cloudflare_account_id="$CLOUDFLARE_ACCOUNT_ID"
```

### Cloudflare API Token Permissions

Create an API token with these permissions:

| Permission | Access |
|------------|--------|
| Account > Cloudflare Pages | Edit |
| Zone > DNS | Edit |
| Zone > Zone | Read |

Restrict to specific zone: `staticshop.io`

### Tools Required

- **Terraform** >= 1.0
- **Wrangler CLI** >= 3.0
- **Hugo** >= 0.120.0 (extended version recommended)

## Infrastructure Setup

### 1. Initialize Terraform

```bash
cd terraform/environments/prod
terraform init
```

### 2. Plan and Apply

```bash
# Review changes
terraform plan

# Apply infrastructure
terraform apply
```

This creates:
- Cloudflare Pages project: `staticshop-marketing`
- Custom domain: `staticshop.io`
- WWW redirect: `www.staticshop.io`
- DNS CNAME records pointing to Pages

## Deployment Methods

### Method 1: GitHub Actions (Recommended)

The automated workflow triggers on:
- Push to main branch (production)
- Push to other branches (preview)
- Manual dispatch

Workflow file: `.github/workflows/deploy-hugo.yml`

**Required GitHub Secrets:**
- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

### Method 2: Manual Deployment (Scripts)

```bash
# 1. Build the site
./scripts/hugo-build.sh

# 2. Deploy to Cloudflare Pages
export CLOUDFLARE_API_TOKEN="your-token"
export CLOUDFLARE_ACCOUNT_ID="your-account-id"
./scripts/deploy-pages.sh -p staticshop-marketing
```

### Method 3: Direct Wrangler CLI

```bash
# Build
hugo --minify

# Deploy
wrangler pages deploy public/ --project-name=staticshop-marketing
```

## Build Configuration

### Hugo Build Settings

| Setting | Value |
|---------|-------|
| Build command | `hugo --minify` |
| Output directory | `public` |
| Production branch | `main` |

### Environment Variables

| Variable | Production | Preview |
|----------|------------|---------|
| HUGO_ENV | production | preview |

## DNS Configuration

| Record | Type | Value | Proxied |
|--------|------|-------|---------|
| @ | CNAME | staticshop-marketing.pages.dev | Yes |
| www | CNAME | staticshop-marketing.pages.dev | Yes |

## Cache Invalidation

Cloudflare Pages automatically purges cache on each deployment. No manual cache invalidation is required.

For aggressive cache control, use Cloudflare Page Rules or Cache Rules in the dashboard.

## Rollback Procedure

### Option 1: Using Rollback Script

```bash
# List recent deployments
./scripts/rollback-pages.sh -l

# Rollback to specific deployment
./scripts/rollback-pages.sh <DEPLOYMENT_ID>
```

### Option 2: Using Wrangler CLI

```bash
# List deployments
wrangler pages deployment list --project-name=staticshop-marketing

# Rollback (creates new deployment from previous)
wrangler pages deployment rollback --project-name=staticshop-marketing <DEPLOYMENT_ID>
```

### Option 3: Cloudflare Dashboard

1. Go to **Pages** > **staticshop-marketing** > **Deployments**
2. Find the desired deployment
3. Click **"..."** menu > **"Rollback to this deployment"**

## Monitoring

### Deployment Status

- **GitHub Actions**: Check workflow runs in Actions tab
- **Cloudflare Dashboard**: Pages > staticshop-marketing > Deployments

### Metrics

View analytics in Cloudflare Dashboard:
- **Pages Analytics**: Traffic, requests, bandwidth
- **Web Analytics**: Page views, visitors, performance

## Troubleshooting

### Build Failures

1. Check Hugo version compatibility
2. Verify all theme dependencies are available
3. Review build logs in GitHub Actions or Wrangler output

### DNS Issues

1. Verify DNS records in Cloudflare dashboard
2. Check that proxy (orange cloud) is enabled
3. Wait for DNS propagation (usually instant with Cloudflare)

### Custom Domain Not Working

1. Verify domain is added in Pages project settings
2. Check DNS CNAME record points to correct pages.dev URL
3. Ensure SSL/TLS is set to "Full" or "Full (strict)"

### Deployment Timeouts

1. Reduce build output size
2. Remove unnecessary files from public directory
3. Check Wrangler version is up to date

## Security Considerations

- Store API tokens as secrets, never in code
- Use scoped API tokens with minimal permissions
- Enable Cloudflare WAF for additional protection
- Review access controls in Cloudflare dashboard

## CI/CD Integration

### GitHub Actions Workflow

The workflow supports:
- Automatic production deployments on main branch
- Preview deployments on feature branches
- Manual deployments via workflow_dispatch
- Repository dispatch for external triggers

### Environment Protection

For production deployments, consider:
- Required reviewers for main branch
- Environment protection rules in GitHub
- Branch protection rules

## Files Reference

| File | Purpose |
|------|---------|
| `terraform/modules/cloudflare-pages/` | Terraform module for Pages |
| `terraform/environments/prod/main.tf` | Production configuration |
| `.github/workflows/deploy-hugo.yml` | CI/CD workflow |
| `scripts/hugo-build.sh` | Hugo build script |
| `scripts/deploy-pages.sh` | Deployment script |
| `scripts/rollback-pages.sh` | Rollback script |

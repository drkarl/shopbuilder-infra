# Cloudflare Services Module

This Terraform module manages Cloudflare services including R2 object storage, Pages deployments, Custom Hostnames (for multi-tenant SaaS), and provides API endpoint information for Cache Purge operations.

## Features

- **R2 Storage**: S3-compatible object storage buckets
- **Pages Projects**: Frontend deployment with Direct Upload API support
- **Custom Hostnames**: Multi-tenant custom domain management with SSL
- **API Endpoints**: Output API endpoints for Cache Purge and other operations

## API Token Requirements

Create a Cloudflare API token with the following scopes:

| Scope | Permission | Purpose |
|-------|------------|---------|
| Zone:DNS:Edit | Edit | DNS record management (via dns module) |
| Account:Cloudflare Pages:Edit | Edit | Pages deployment |
| Account:R2:Edit | Edit | R2 storage operations |
| Zone:SSL and Certificates:Edit | Edit | Custom Hostnames API |
| Zone:Cache Purge:Purge | Purge | Cache invalidation |

## Usage

### Basic R2 Bucket

```hcl
module "cloudflare" {
  source = "../../modules/cloudflare"

  account_id  = var.cloudflare_account_id
  environment = "prod"

  r2_bucket = {
    name     = "shopbuilder-assets-prod"
    location = "WEUR"  # Western Europe
  }
}
```

### Pages Project with Direct Upload

```hcl
module "cloudflare" {
  source = "../../modules/cloudflare"

  account_id  = var.cloudflare_account_id
  zone_name   = "example.com"
  environment = "prod"

  pages_project = {
    name              = "shopbuilder-frontend"
    production_branch = "main"
    custom_domain     = "app.example.com"
  }
}
```

### Pages Project with GitHub Integration

```hcl
module "cloudflare" {
  source = "../../modules/cloudflare"

  account_id  = var.cloudflare_account_id
  zone_name   = "example.com"
  environment = "prod"

  pages_project = {
    name              = "shopbuilder-frontend"
    production_branch = "main"
    custom_domain     = "app.example.com"

    build_command   = "npm run build"
    destination_dir = "dist"
    root_dir        = "/"

    github_repo = {
      owner = "myorg"
      name  = "frontend"
    }

    env_vars = {
      NODE_ENV = "production"
      API_URL  = "https://api.example.com"
    }
  }
}
```

### Custom Hostnames for Multi-Tenant SaaS

```hcl
module "cloudflare" {
  source = "../../modules/cloudflare"

  account_id  = var.cloudflare_account_id
  zone_name   = "example.com"
  environment = "prod"

  custom_hostnames = {
    customer1 = {
      hostname   = "shop.customer1.com"
      ssl_method = "http"
      ssl_type   = "dv"
    }
    customer2 = {
      hostname     = "store.customer2.com"
      ssl_method   = "txt"
      ssl_type     = "dv"
      wait_for_ssl = true
      ssl_settings = {
        min_tls_version = "1.2"
        http2           = "on"
        tls_1_3         = "on"
      }
      metadata = {
        tenant_id = "customer-2"
        plan      = "enterprise"
      }
    }
  }
}
```

### Complete Configuration

```hcl
module "cloudflare" {
  source = "../../modules/cloudflare"

  account_id  = var.cloudflare_account_id
  zone_name   = "staticshop.io"
  environment = "prod"

  # R2 bucket for assets
  r2_bucket = {
    name     = "shopbuilder-assets-prod"
    location = "WEUR"
  }

  # Pages project
  pages_project = {
    name              = "shopbuilder-frontend"
    production_branch = "main"
    custom_domain     = "app.staticshop.io"
  }

  # Custom hostnames for tenants
  custom_hostnames = {
    tenant1 = {
      hostname = "shop.tenant1.com"
    }
  }
}
```

## R2 Configuration Details

### Location Codes

| Code | Region |
|------|--------|
| WNAM | Western North America |
| ENAM | Eastern North America |
| WEUR | Western Europe |
| EEUR | Eastern Europe |
| APAC | Asia Pacific |
| OC | Oceania |

### S3 Client Configuration (Java/Spring Boot)

```java
// Variables injected via @Value annotations from application.properties:
// @Value("${cloudflare.account-id}") String accountId
// @Value("${r2.access-key-id}") String r2AccessKeyId
// @Value("${r2.secret-access-key}") String r2SecretAccessKey
// See docs/cloudflare-services.md for complete R2Config class example.
S3Client s3Client = S3Client.builder()
    .endpointOverride(URI.create("https://" + accountId + ".r2.cloudflarestorage.com"))
    .region(Region.of("auto"))
    .credentialsProvider(StaticCredentialsProvider.create(
        AwsBasicCredentials.create(r2AccessKeyId, r2SecretAccessKey)))
    .build();
```

### Environment Variables for R2

```bash
R2_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com
R2_ACCESS_KEY_ID=<access-key>
R2_SECRET_ACCESS_KEY=<secret-key>
R2_BUCKET_NAME=shopbuilder-assets-prod
```

## Cache Purge API

The module outputs the Cache Purge API endpoint. Use it programmatically:

```bash
# Purge specific URLs
curl -X POST "https://api.cloudflare.com/client/v4/zones/{zone_id}/purge_cache" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"files":["https://example.com/path/to/file"]}'

# Purge everything
curl -X POST "https://api.cloudflare.com/client/v4/zones/{zone_id}/purge_cache" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"purge_everything":true}'

# Purge by tag (Enterprise only)
curl -X POST "https://api.cloudflare.com/client/v4/zones/{zone_id}/purge_cache" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"tags":["product-123"]}'
```

## Custom Hostnames API

For programmatic custom hostname management:

```bash
# Create custom hostname
curl -X POST "https://api.cloudflare.com/client/v4/zones/{zone_id}/custom_hostnames" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{
    "hostname": "shop.customer.com",
    "ssl": {
      "method": "http",
      "type": "dv"
    }
  }'

# List custom hostnames
curl "https://api.cloudflare.com/client/v4/zones/{zone_id}/custom_hostnames" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN"

# Delete custom hostname
curl -X DELETE "https://api.cloudflare.com/client/v4/zones/{zone_id}/custom_hostnames/{hostname_id}" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN"
```

## Pages Direct Upload API

For CI/CD deployments without GitHub integration:

```bash
# Create deployment (upload assets)
curl -X POST "https://api.cloudflare.com/client/v4/accounts/{account_id}/pages/projects/{project_name}/deployments" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -F "manifest=@manifest.json" \
  -F "<file_hash>=@path/to/file"

# List deployments
curl "https://api.cloudflare.com/client/v4/accounts/{account_id}/pages/projects/{project_name}/deployments" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN"
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| account_id | Cloudflare Account ID | `string` | - | yes |
| zone_name | DNS zone name (domain) | `string` | `null` | no |
| environment | Environment name (dev, staging, prod) | `string` | - | yes |
| r2_bucket | R2 bucket configuration | `object` | `null` | no |
| pages_project | Cloudflare Pages project configuration | `object` | `null` | no |
| custom_hostnames | Custom hostnames for multi-tenant domains | `map(object)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| r2_bucket_name | Name of the created R2 bucket |
| r2_bucket_id | ID of the created R2 bucket |
| r2_bucket_location | Location of the R2 bucket |
| r2_endpoint | S3-compatible endpoint URL for R2 bucket |
| pages_project_name | Name of the Pages project |
| pages_project_id | ID of the Pages project |
| pages_subdomain | Default subdomain for the Pages project |
| pages_domains | All domains associated with the Pages project |
| pages_custom_domain | Custom domain attached to the Pages project |
| pages_custom_domain_status | Status of the custom domain |
| custom_hostnames | Map of custom hostname configurations |
| custom_hostname_ids | Map of custom hostname IDs |
| zone_id | Zone ID for API operations |
| zone_name | Zone name |
| api_endpoints | Cloudflare API endpoints for programmatic access |

## Required Secrets (SOPS)

Add these to your encrypted secrets file:

```yaml
# Cloudflare API Token (with required scopes)
CLOUDFLARE_API_TOKEN: cf_xxxxxxxxxxxxxxxxxxxx

# Cloudflare Account ID (32 hex characters)
CLOUDFLARE_ACCOUNT_ID: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# R2 Access Credentials (S3-compatible)
R2_ACCESS_KEY_ID: xxxxxxxxxxxxxxxxxxxx
R2_SECRET_ACCESS_KEY: xxxxxxxxxxxxxxxxxxxx
```

## Notes

- R2 access credentials are separate from the API token and must be generated in the Cloudflare dashboard under R2 > Manage R2 API Tokens
- Custom Hostnames require the zone_name variable to be set
- Pages Direct Upload is used when github_repo is not configured
- Cache Purge is performed via API calls, not Terraform resources

# Cloudflare Pages Module

Reusable Terraform module for managing Cloudflare Pages projects for static site hosting.

## Features

- **Cloudflare Pages project management**: Create and configure Pages projects
- **Custom domain support**: Primary domain and WWW redirect configuration
- **Hugo integration**: Pre-configured for Hugo static site builds
- **Environment variables**: Support for preview and production environments
- **Direct Upload compatible**: Works with Wrangler CLI deployments

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| cloudflare | ~> 4.0 |

## Usage

### Hugo Marketing Site Example

```hcl
module "marketing_site" {
  source = "../../modules/cloudflare-pages"

  account_id   = "your-cloudflare-account-id"
  project_name = "staticshop-marketing"
  environment  = "prod"

  # Hugo build configuration
  build_command          = "hugo --minify"
  build_output_directory = "public"
  production_branch      = "main"

  # Custom domains
  custom_domain       = "staticshop.io"
  www_redirect_domain = "www.staticshop.io"
}

output "site_url" {
  value = module.marketing_site.pages_url
}

output "custom_url" {
  value = "https://${module.marketing_site.custom_domain}"
}
```

### With Environment Variables

```hcl
module "marketing_site" {
  source = "../../modules/cloudflare-pages"

  account_id   = "your-cloudflare-account-id"
  project_name = "staticshop-marketing"
  environment  = "prod"

  build_command          = "hugo --minify"
  build_output_directory = "public"

  enable_deployment_configs = true
  production_environment_variables = {
    HUGO_ENV = "production"
  }
  preview_environment_variables = {
    HUGO_ENV = "preview"
  }
}
```

### Pages.dev Only (No Custom Domain)

```hcl
module "staging_site" {
  source = "../../modules/cloudflare-pages"

  account_id   = "your-cloudflare-account-id"
  project_name = "staticshop-staging"
  environment  = "staging"

  build_command          = "hugo --minify"
  build_output_directory = "public"
  production_branch      = "develop"
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| account_id | Cloudflare account ID | `string` | n/a | yes |
| project_name | Name for the Cloudflare Pages project | `string` | n/a | yes |
| environment | Environment name (dev, staging, prod) | `string` | n/a | yes |
| production_branch | Git branch for production deployments | `string` | `"main"` | no |
| build_command | Command to build the site | `string` | `"hugo --minify"` | no |
| build_output_directory | Directory containing built site | `string` | `"public"` | no |
| build_root_directory | Root directory for the build | `string` | `""` | no |
| custom_domain | Primary custom domain | `string` | `null` | no |
| www_redirect_domain | WWW subdomain for redirect | `string` | `null` | no |
| enable_deployment_configs | Enable environment variables | `bool` | `false` | no |
| preview_environment_variables | Environment variables for preview | `map(string)` | `{}` | no |
| production_environment_variables | Environment variables for production | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| project_id | ID of the Cloudflare Pages project |
| project_name | Name of the Cloudflare Pages project |
| subdomain | Default pages.dev subdomain |
| pages_url | Full pages.dev URL |
| custom_domain | Primary custom domain if configured |
| custom_domain_id | ID of the custom domain resource |
| www_redirect_domain | WWW redirect domain if configured |
| www_redirect_domain_id | ID of the WWW redirect domain resource |
| build_config | Build configuration summary |
| deployment_info | Information needed for CI/CD deployments |

## Deployment Methods

### Method 1: Wrangler CLI (Recommended)

Deploy using Wrangler CLI for Direct Upload:

```bash
# Build the Hugo site
hugo --minify

# Deploy to Cloudflare Pages
wrangler pages deploy public/ --project-name=staticshop-marketing
```

### Method 2: GitHub Actions

See `.github/workflows/deploy-hugo.yml` for automated deployment workflow.

### Method 3: Direct Upload API

```bash
# Upload directory and get deployment ID
curl -X POST \
  "https://api.cloudflare.com/client/v4/accounts/{account_id}/pages/projects/{project_name}/deployments" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -F "manifest=@manifest.json" \
  -F "file=@public.tar.gz"
```

## Custom Domain DNS Configuration

When using custom domains, you need to configure DNS records. Use the DNS module:

```hcl
module "dns" {
  source = "../../modules/dns"

  zone_name   = "staticshop.io"
  environment = "prod"

  marketing_record = {
    subdomain = "@"
    value     = module.marketing_site.subdomain
    type      = "CNAME"
    proxied   = true
    comment   = "Marketing site on Cloudflare Pages"
  }

  custom_records = [
    {
      name    = "www"
      value   = module.marketing_site.subdomain
      type    = "CNAME"
      proxied = true
      comment = "WWW redirect to marketing site"
    }
  ]
}
```

## Cache Invalidation

Cloudflare Pages automatically purges cache on deployment. No manual cache invalidation is needed.

For aggressive cache control, configure cache rules in Cloudflare dashboard or via Terraform cloudflare_ruleset resource.

## Rollback Procedure

To rollback to a previous deployment:

```bash
# List recent deployments
wrangler pages deployment list --project-name=staticshop-marketing

# Rollback to specific deployment
wrangler pages deployment rollback --project-name=staticshop-marketing <deployment-id>
```

Or via Cloudflare Dashboard:
1. Go to Pages > Project > Deployments
2. Find the desired deployment
3. Click "Rollback to this deployment"

## Environment Variables

The Cloudflare provider requires authentication:

```bash
export CLOUDFLARE_API_TOKEN="your-api-token"
export CLOUDFLARE_ACCOUNT_ID="your-account-id"
```

## Integration with Existing Modules

This module works with the DNS module for complete domain configuration:

```hcl
# Create the Pages project
module "marketing_site" {
  source = "../../modules/cloudflare-pages"
  # ... configuration
}

# Configure DNS to point to Pages
module "dns" {
  source = "../../modules/dns"

  zone_name   = "staticshop.io"
  environment = "prod"

  marketing_record = {
    subdomain = "@"
    value     = "${module.marketing_site.project_name}.pages.dev"
    type      = "CNAME"
    proxied   = true
  }
}
```

## License

This module is part of the shopbuilder-infra project.

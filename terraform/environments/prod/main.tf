# Production Environment
# Main configuration for the production environment

terraform {
  required_version = ">= 1.0"

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "~> 0.40"
    }

    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }

    neon = {
      source  = "kislerdm/neon"
      version = "~> 0.6"
    }

    upstash = {
      source  = "upstash/upstash"
      version = "~> 2.0"
    }
  }
}

# OVH Provider
provider "ovh" {
  endpoint = var.ovh_endpoint
}

# Scaleway Provider
provider "scaleway" {
  region = var.scaleway_region
  zone   = var.scaleway_zone
}

# Cloudflare Provider
# Authentication via CLOUDFLARE_API_TOKEN environment variable
provider "cloudflare" {}

# Neon Provider
# Authentication via NEON_API_KEY environment variable
provider "neon" {}

# Upstash Provider
# Set TF_VAR_upstash_email and TF_VAR_upstash_api_key environment variables or use .tfvars
provider "upstash" {
  email   = var.upstash_email
  api_key = var.upstash_api_key
}

locals {
  environment = "prod"
  common_tags = merge(var.common_tags, {
    Environment = local.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  })
}

#------------------------------------------------------------------------------
# Cloudflare Pages - Marketing Site (staticshop.io)
#------------------------------------------------------------------------------

module "marketing_site" {
  source = "../../modules/cloudflare-pages"

  account_id   = var.cloudflare_account_id
  project_name = "staticshop-marketing"
  environment  = local.environment

  # Hugo build configuration
  build_command          = "hugo --minify"
  build_output_directory = "public"
  production_branch      = "main"

  # Custom domains
  custom_domain       = "staticshop.io"
  www_redirect_domain = "www.staticshop.io"

  # Environment variables for Hugo builds
  enable_deployment_configs = true
  production_environment_variables = {
    HUGO_ENV = "production"
  }
  preview_environment_variables = {
    HUGO_ENV = "preview"
  }
}

#------------------------------------------------------------------------------
# DNS Configuration for Marketing Site
#------------------------------------------------------------------------------

module "dns" {
  source = "../../modules/dns"

  zone_name   = "staticshop.io"
  environment = local.environment

  # Marketing site: staticshop.io -> Cloudflare Pages
  marketing_record = {
    subdomain = "@"
    value     = "${module.marketing_site.subdomain}.pages.dev"
    type      = "CNAME"
    proxied   = true
    comment   = "Marketing site on Cloudflare Pages"
  }

  # WWW redirect: www.staticshop.io -> Cloudflare Pages
  custom_records = [
    {
      name    = "www"
      value   = "${module.marketing_site.subdomain}.pages.dev"
      type    = "CNAME"
      proxied = true
      comment = "WWW redirect to marketing site"
    },
    # Woodpecker CI server: ci.staticshop.io
    # Note: Update 'value' with the actual VPS IP when provisioned
    {
      name    = "ci"
      value   = var.woodpecker_server_ip
      type    = "A"
      proxied = true
      comment = "Woodpecker CI server"
    }
  ]
}

#------------------------------------------------------------------------------
# Neon PostgreSQL Database
#------------------------------------------------------------------------------

module "neon_database" {
  source = "../../modules/neon-postgres"

  project_name = "${var.project_name}-${local.environment}"
  environment  = local.environment
  org_id       = var.neon_org_id
  region_id    = var.neon_region_id

  # Database configuration
  database_name = var.neon_database_name
  database_role = var.neon_database_role
  pg_version    = var.neon_pg_version

  # Production compute settings (higher resources)
  autoscaling_min_cu      = var.neon_autoscaling_min_cu
  autoscaling_max_cu      = var.neon_autoscaling_max_cu
  suspend_timeout_seconds = var.neon_suspend_timeout_seconds

  # Data retention (7 days for production PITR)
  history_retention_seconds = var.neon_history_retention_seconds

  # Security: IP allow list (empty = allow all)
  allowed_ips = var.neon_allowed_ips
}

#------------------------------------------------------------------------------
# Upstash Redis - Caching and Session Management
#------------------------------------------------------------------------------

module "redis" {
  source = "../../modules/upstash-redis"

  database_name    = "${var.project_name}-${local.environment}"
  region           = var.upstash_redis_region
  environment      = local.environment
  tls_enabled      = true
  eviction_enabled = true
  auto_scale       = false
}

# Add additional module calls here as infrastructure grows
# Example:
# module "vps" {
#   source       = "../../modules/vps"
#   name         = "${var.project_name}-${local.environment}"
#   environment  = local.environment
#   instance_type = var.vps_instance_type
#   region       = var.scaleway_region
#   tags         = local.common_tags
# }

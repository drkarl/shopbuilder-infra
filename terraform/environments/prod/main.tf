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
    value     = "${module.marketing_site.project_name}.pages.dev"
    type      = "CNAME"
    proxied   = true
    comment   = "Marketing site on Cloudflare Pages"
  }

  # WWW redirect: www.staticshop.io -> Cloudflare Pages
  custom_records = [
    {
      name    = "www"
      value   = "${module.marketing_site.project_name}.pages.dev"
      type    = "CNAME"
      proxied = true
      comment = "WWW redirect to marketing site"
    }
  ]
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

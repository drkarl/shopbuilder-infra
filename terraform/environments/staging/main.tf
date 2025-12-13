# Staging Environment
# Main configuration for the staging environment

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
  environment = "staging"
  common_tags = merge(var.common_tags, {
    Environment = local.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  })
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

  # Staging compute settings (smaller than production)
  autoscaling_min_cu      = var.neon_autoscaling_min_cu
  autoscaling_max_cu      = var.neon_autoscaling_max_cu
  suspend_timeout_seconds = var.neon_suspend_timeout_seconds

  # Data retention (1 day for staging PITR)
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

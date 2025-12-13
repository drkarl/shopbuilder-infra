# Upstash Redis Module
# This module provisions an Upstash Redis database for caching and session management

terraform {
  required_version = ">= 1.0"

  required_providers {
    upstash = {
      source  = "upstash/upstash"
      version = "~> 2.0"
    }
  }
}

#------------------------------------------------------------------------------
# Upstash Redis Database
#------------------------------------------------------------------------------

resource "upstash_redis_database" "this" {
  database_name = var.database_name
  region        = var.region
  tls           = var.tls_enabled
  eviction      = var.eviction_enabled
  auto_scale    = var.auto_scale

  # Global database configuration (optional)
  primary_region = var.primary_region
  read_regions   = var.read_regions
}

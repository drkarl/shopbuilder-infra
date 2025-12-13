# Cloudflare Services Module
# This module manages Cloudflare services including R2 storage, Pages, Custom Hostnames, and Cache Purge
#
# Required API Token Scopes:
# - Zone:DNS:Edit              - DNS record management (handled by dns module)
# - Account:Cloudflare Pages:Edit - Pages deployment
# - Account:R2:Edit           - R2 storage operations
# - Zone:SSL and Certificates:Edit - Custom Hostnames API
# - Zone:Cache Purge:Purge    - Cache invalidation

terraform {
  required_version = ">= 1.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

#------------------------------------------------------------------------------
# Data Sources
#------------------------------------------------------------------------------

# Look up the zone ID from the zone name
data "cloudflare_zone" "this" {
  count = var.zone_name != null ? 1 : 0
  name  = var.zone_name
}

#------------------------------------------------------------------------------
# R2 Bucket
# S3-compatible object storage
#------------------------------------------------------------------------------

resource "cloudflare_r2_bucket" "this" {
  count = var.r2_bucket != null ? 1 : 0

  account_id = var.account_id
  name       = var.r2_bucket.name
  location   = var.r2_bucket.location
}

#------------------------------------------------------------------------------
# Cloudflare Pages Project
# For frontend deployments via Direct Upload API
#------------------------------------------------------------------------------

resource "cloudflare_pages_project" "this" {
  count = var.pages_project != null ? 1 : 0

  account_id        = var.account_id
  name              = var.pages_project.name
  production_branch = var.pages_project.production_branch

  dynamic "build_config" {
    for_each = var.pages_project.build_command != null ? [1] : []
    content {
      build_command   = var.pages_project.build_command
      destination_dir = var.pages_project.destination_dir
      root_dir        = var.pages_project.root_dir
    }
  }

  dynamic "source" {
    for_each = var.pages_project.github_repo != null ? [1] : []
    content {
      type = "github"
      config {
        owner                         = var.pages_project.github_repo.owner
        repo_name                     = var.pages_project.github_repo.name
        production_branch             = var.pages_project.production_branch
        pr_comments_enabled           = var.pages_project.github_repo.pr_comments_enabled
        deployments_enabled           = var.pages_project.github_repo.deployments_enabled
        production_deployment_enabled = var.pages_project.github_repo.production_deployment_enabled
        preview_deployment_setting    = var.pages_project.github_repo.preview_deployment_setting
        preview_branch_includes       = var.pages_project.github_repo.preview_branch_includes
        preview_branch_excludes       = var.pages_project.github_repo.preview_branch_excludes
      }
    }
  }

  dynamic "deployment_configs" {
    for_each = var.pages_project.env_vars != null || var.pages_project.compatibility_date != null ? [1] : []
    content {
      production {
        compatibility_date  = var.pages_project.compatibility_date
        compatibility_flags = var.pages_project.compatibility_flags
        environment_variables = var.pages_project.env_vars
      }
    }
  }
}

#------------------------------------------------------------------------------
# Pages Custom Domain
# Connect custom domain to Pages project
#------------------------------------------------------------------------------

resource "cloudflare_pages_domain" "this" {
  count = var.pages_project != null && var.pages_project.custom_domain != null ? 1 : 0

  account_id   = var.account_id
  project_name = cloudflare_pages_project.this[0].name
  domain       = var.pages_project.custom_domain
}

#------------------------------------------------------------------------------
# Custom Hostnames
# For multi-tenant SaaS custom domains
#------------------------------------------------------------------------------

resource "cloudflare_custom_hostname" "this" {
  for_each = var.custom_hostnames

  zone_id  = data.cloudflare_zone.this[0].id
  hostname = each.value.hostname

  ssl {
    method = each.value.ssl_method
    type   = each.value.ssl_type

    dynamic "settings" {
      for_each = each.value.ssl_settings != null ? [each.value.ssl_settings] : []
      content {
        min_version = settings.value.min_tls_version
        ciphers     = settings.value.ciphers
        early_hints = settings.value.early_hints
        http2       = settings.value.http2
        tls_1_3     = settings.value.tls_1_3
      }
    }
  }

  custom_metadata = each.value.metadata

  wait_for_ssl_pending_validation = each.value.wait_for_ssl
}

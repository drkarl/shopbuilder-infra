# Neon PostgreSQL Module
# This module manages Neon PostgreSQL projects for serverless database hosting

terraform {
  required_version = ">= 1.0"

  required_providers {
    neon = {
      source  = "kislerdm/neon"
      version = "~> 0.6"
    }
  }
}

#------------------------------------------------------------------------------
# Neon Project
# Creates a Neon PostgreSQL project with configured compute and pooling settings
#------------------------------------------------------------------------------

resource "neon_project" "this" {
  name      = var.project_name
  region_id = var.region_id
  org_id    = var.org_id

  lifecycle {
    precondition {
      condition     = var.autoscaling_min_cu <= var.autoscaling_max_cu
      error_message = "autoscaling_min_cu (${var.autoscaling_min_cu}) must be less than or equal to autoscaling_max_cu (${var.autoscaling_max_cu})."
    }
  }

  pg_version                 = var.pg_version
  history_retention_seconds  = var.history_retention_seconds
  store_password             = "yes" # pragma: allowlist secret
  enable_logical_replication = var.enable_logical_replication ? "yes" : "no"

  # Default branch configuration
  branch {
    name          = var.default_branch_name
    database_name = var.database_name
    role_name     = var.database_role
  }

  # Default endpoint (compute) configuration
  default_endpoint_settings {
    autoscaling_limit_min_cu = var.autoscaling_min_cu
    autoscaling_limit_max_cu = var.autoscaling_max_cu
    suspend_timeout_seconds  = var.suspend_timeout_seconds
  }

  # IP allow list for security (if configured)
  allowed_ips                         = var.allowed_ips
  allowed_ips_protected_branches_only = var.allowed_ips_protected_branches_only ? "yes" : "no"
}

#------------------------------------------------------------------------------
# Project Configuration
#------------------------------------------------------------------------------

variable "project_name" {
  description = "Name for the Neon project"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$", var.project_name))
    error_message = "Project name must be lowercase alphanumeric with hyphens, 2-63 characters, start/end with alphanumeric."
  }
}

variable "region_id" {
  description = "Neon region identifier (e.g., aws-us-east-1, aws-eu-central-1)"
  type        = string
  default     = "aws-eu-central-1"

  validation {
    condition     = can(regex("^aws-[a-z]{2}-[a-z]+-[0-9]+$", var.region_id))
    error_message = "Region ID must be a valid Neon region (e.g., aws-us-east-1, aws-eu-central-1)."
  }
}

variable "org_id" {
  description = "Neon organization ID. Required to ensure project is created in the correct organization."
  type        = string

  validation {
    condition     = can(regex("^org-[a-z0-9-]+$", var.org_id))
    error_message = "Organization ID must be in the format 'org-<id>'."
  }
}

variable "pg_version" {
  description = "PostgreSQL version (15, 16, 17)"
  type        = number
  default     = 16

  validation {
    condition     = contains([15, 16, 17], var.pg_version)
    error_message = "PostgreSQL version must be 15, 16, or 17."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

#------------------------------------------------------------------------------
# Database Configuration
#------------------------------------------------------------------------------

variable "default_branch_name" {
  description = "Name for the default branch"
  type        = string
  default     = "main"
}

variable "database_name" {
  description = "Name of the default database"
  type        = string
  default     = "shopbuilder"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name))
    error_message = "Database name must start with a letter, contain only lowercase letters, numbers, and underscores, max 63 characters."
  }
}

variable "database_role" {
  description = "Name of the default database role"
  type        = string
  default     = "shopbuilder"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_role))
    error_message = "Role name must start with a letter, contain only lowercase letters, numbers, and underscores, max 63 characters."
  }
}

#------------------------------------------------------------------------------
# Compute Configuration
#------------------------------------------------------------------------------

variable "autoscaling_min_cu" {
  description = "Minimum compute units (0.25, 0.5, 1, 2, etc.)"
  type        = number
  default     = 0.25

  validation {
    condition     = var.autoscaling_min_cu >= 0.25 && var.autoscaling_min_cu <= 10
    error_message = "Minimum compute units must be between 0.25 and 10."
  }
}

variable "autoscaling_max_cu" {
  description = "Maximum compute units (0.25, 0.5, 1, 2, etc.)"
  type        = number
  default     = 1

  validation {
    condition     = var.autoscaling_max_cu >= 0.25 && var.autoscaling_max_cu <= 10
    error_message = "Maximum compute units must be between 0.25 and 10."
  }
}

variable "suspend_timeout_seconds" {
  description = "Seconds of inactivity before compute suspends (0 to disable, minimum 60 when enabled)"
  type        = number
  default     = 300

  validation {
    condition     = var.suspend_timeout_seconds == 0 || var.suspend_timeout_seconds >= 60
    error_message = "Suspend timeout must be 0 (disabled) or at least 60 seconds."
  }
}

#------------------------------------------------------------------------------
# Data Retention
#------------------------------------------------------------------------------

variable "history_retention_seconds" {
  description = "Point-in-time restore history retention in seconds (default 86400 = 1 day)"
  type        = number
  default     = 86400

  validation {
    condition     = var.history_retention_seconds >= 3600 && var.history_retention_seconds <= 2592000
    error_message = "History retention must be between 3600 (1 hour) and 2592000 (30 days) seconds."
  }
}

variable "enable_logical_replication" {
  description = "Enable WAL-level logical replication (required for CDC, increases storage)"
  type        = bool
  default     = false
}

#------------------------------------------------------------------------------
# Security Configuration
#------------------------------------------------------------------------------

variable "allowed_ips" {
  description = "List of IP addresses/ranges allowed to connect (CIDR notation). Empty list allows all."
  type        = list(string)
  default     = []
}

variable "allowed_ips_protected_branches_only" {
  description = "Apply IP allow list only to protected branches"
  type        = bool
  default     = false
}

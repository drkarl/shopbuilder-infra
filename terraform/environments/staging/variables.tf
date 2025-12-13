# Staging Environment Variables

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "shopbuilder"
}

# OVH Provider Variables
variable "ovh_endpoint" {
  description = "OVH API endpoint (ovh-eu, ovh-ca, ovh-us, etc.)"
  type        = string
  default     = "ovh-eu"
}

# Scaleway Provider Variables
variable "scaleway_region" {
  description = "Scaleway region"
  type        = string
  default     = "fr-par"
}

variable "scaleway_zone" {
  description = "Scaleway availability zone"
  type        = string
  default     = "fr-par-1"
}

# Common Tags
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# VPS Configuration
variable "vps_instance_type" {
  description = "Instance type for VPS (Scaleway instance type)"
  type        = string
  default     = "DEV1-M"
}

#------------------------------------------------------------------------------
# Neon PostgreSQL Configuration
#------------------------------------------------------------------------------

variable "neon_org_id" {
  description = "Neon organization ID"
  type        = string

  validation {
    condition     = can(regex("^org-[a-z0-9-]+$", var.neon_org_id))
    error_message = "Organization ID must be in the format 'org-<id>'."
  }
}

variable "neon_region_id" {
  description = "Neon region for database deployment"
  type        = string
  default     = "aws-eu-central-1"
}

variable "neon_database_name" {
  description = "Name of the default database"
  type        = string
  default     = "shopbuilder"
}

variable "neon_database_role" {
  description = "Name of the default database role"
  type        = string
  default     = "shopbuilder"
}

variable "neon_pg_version" {
  description = "PostgreSQL version"
  type        = number
  default     = 16
}

variable "neon_autoscaling_min_cu" {
  description = "Minimum compute units for autoscaling"
  type        = number
  default     = 0.25
}

variable "neon_autoscaling_max_cu" {
  description = "Maximum compute units for autoscaling"
  type        = number
  default     = 1
}

variable "neon_suspend_timeout_seconds" {
  description = "Seconds of inactivity before compute suspends (0 to disable)"
  type        = number
  default     = 300
}

variable "neon_history_retention_seconds" {
  description = "Point-in-time restore retention period in seconds (default 1 day)"
  type        = number
  default     = 86400
}

variable "neon_allowed_ips" {
  description = "List of IP addresses/ranges allowed to connect (empty = allow all)"
  type        = list(string)
  default     = []
}

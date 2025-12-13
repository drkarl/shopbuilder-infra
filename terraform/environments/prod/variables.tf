# Production Environment Variables

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

# Cloudflare Provider Variables
variable "cloudflare_account_id" {
  description = "Cloudflare account ID for Pages and DNS management"
  type        = string

  validation {
    condition     = can(regex("^[a-f0-9]{32}$", var.cloudflare_account_id))
    error_message = "Cloudflare account ID must be a 32-character hexadecimal string."
  }
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
  default     = "GP1-S"
}

#------------------------------------------------------------------------------
# Woodpecker CI Configuration
#------------------------------------------------------------------------------

variable "woodpecker_server_ip" {
  description = "Public IPv4 address of the Woodpecker CI server VPS"
  type        = string

  validation {
    condition     = can(regex("^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$", var.woodpecker_server_ip))
    error_message = "Woodpecker server IP must be a valid IPv4 address."
  }
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
  default     = 0.5
}

variable "neon_autoscaling_max_cu" {
  description = "Maximum compute units for autoscaling"
  type        = number
  default     = 2
}

variable "neon_suspend_timeout_seconds" {
  description = "Seconds of inactivity before compute suspends (0 to disable)"
  type        = number
  default     = 0
}

variable "neon_history_retention_seconds" {
  description = "Point-in-time restore retention period in seconds (default 7 days)"
  type        = number
  default     = 604800
}

variable "neon_allowed_ips" {
  description = "List of IP addresses/ranges allowed to connect (empty = allow all)"
  type        = list(string)
  default     = []
}

#------------------------------------------------------------------------------
# Upstash Provider Variables
#------------------------------------------------------------------------------

variable "upstash_email" {
  description = "Email address registered with Upstash"
  type        = string
  sensitive   = true
}

variable "upstash_api_key" {
  description = "Upstash API key from console"
  type        = string
  sensitive   = true
}

variable "upstash_redis_region" {
  description = "Region for Upstash Redis database"
  type        = string
  default     = "eu-west-1"
}

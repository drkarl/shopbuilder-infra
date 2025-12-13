variable "database_name" {
  description = "Name of the Upstash Redis database"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_-]*$", var.database_name))
    error_message = "Database name must start with a letter and contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "region" {
  description = "Region for the Redis database. Use 'global' for multi-region deployment."
  type        = string

  validation {
    condition = contains([
      "global",
      "eu-west-1",
      "us-east-1",
      "us-west-1",
      "us-west-2",
      "ap-northeast-1",
      "ap-southeast-1",
      "ap-southeast-2",
      "eu-central-1",
      "sa-east-1"
    ], var.region)
    error_message = "Region must be one of: global, eu-west-1, us-east-1, us-west-1, us-west-2, ap-northeast-1, ap-southeast-1, ap-southeast-2, eu-central-1, sa-east-1."
  }
}

variable "tls_enabled" {
  description = "Enable TLS encryption for connections. Required for production use."
  type        = bool
  default     = true

  validation {
    condition     = var.tls_enabled == true
    error_message = "TLS must be enabled for security. Upstash uses 'rediss://' protocol with TLS."
  }
}

variable "eviction_enabled" {
  description = "Enable key eviction when database reaches max size. Recommended for caching workloads."
  type        = bool
  default     = true
}

variable "auto_scale" {
  description = "Automatically upgrade to higher plans when hitting quotas"
  type        = bool
  default     = false
}

#------------------------------------------------------------------------------
# Global Database Configuration (optional)
#------------------------------------------------------------------------------

variable "primary_region" {
  description = "Primary region for global database deployment. Only used when region is 'global'."
  type        = string
  default     = null

  validation {
    condition = var.primary_region == null || contains([
      "us-east-1",
      "us-west-1",
      "us-west-2",
      "eu-central-1",
      "eu-west-1",
      "sa-east-1",
      "ap-southeast-1",
      "ap-southeast-2"
    ], var.primary_region)
    error_message = "Primary region must be one of: us-east-1, us-west-1, us-west-2, eu-central-1, eu-west-1, sa-east-1, ap-southeast-1, ap-southeast-2."
  }
}

variable "read_regions" {
  description = "Read replica regions for global database. Must not include the primary region."
  type        = set(string)
  default     = null
}

#------------------------------------------------------------------------------
# Metadata
#------------------------------------------------------------------------------

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

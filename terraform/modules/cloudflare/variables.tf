variable "account_id" {
  description = "Cloudflare Account ID"
  type        = string

  validation {
    condition     = can(regex("^[a-f0-9]{32}$", var.account_id))
    error_message = "Account ID must be a 32-character hexadecimal string."
  }
}

variable "zone_name" {
  description = "DNS zone name (domain), e.g., 'example.com'. Required for custom hostnames."
  type        = string
  default     = null

  validation {
    condition     = var.zone_name == null || can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.zone_name))
    error_message = "Zone name must be a valid domain name (e.g., 'example.com')."
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
# R2 Bucket Configuration
#------------------------------------------------------------------------------

variable "r2_bucket" {
  description = "R2 bucket configuration for S3-compatible object storage"
  type = object({
    name     = string
    location = optional(string, "WEUR") # Western Europe default
  })
  default = null

  validation {
    condition = var.r2_bucket == null || can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.r2_bucket.name))
    error_message = "R2 bucket name must be 3-63 characters, lowercase alphanumeric and hyphens, start and end with alphanumeric."
  }

  validation {
    condition = var.r2_bucket == null || contains(
      ["WNAM", "ENAM", "WEUR", "EEUR", "APAC", "OC"],
      var.r2_bucket.location
    )
    error_message = "R2 location must be one of: WNAM (Western North America), ENAM (Eastern North America), WEUR (Western Europe), EEUR (Eastern Europe), APAC (Asia Pacific), OC (Oceania)."
  }
}

#------------------------------------------------------------------------------
# Pages Project Configuration
#------------------------------------------------------------------------------

variable "pages_project" {
  description = "Cloudflare Pages project configuration for frontend deployments"
  type = object({
    name              = string
    production_branch = optional(string, "main")
    custom_domain     = optional(string)

    # Build configuration (optional - for Direct Upload, leave null)
    build_command   = optional(string)
    destination_dir = optional(string)
    root_dir        = optional(string)

    # GitHub integration (optional)
    github_repo = optional(object({
      owner                         = string
      name                          = string
      pr_comments_enabled           = optional(bool, true)
      deployments_enabled           = optional(bool, true)
      production_deployment_enabled = optional(bool, true)
      preview_deployment_setting    = optional(string, "all")
      preview_branch_includes       = optional(list(string), ["*"])
      preview_branch_excludes       = optional(list(string), [])
    }))

    # Deployment configuration
    compatibility_date  = optional(string)
    compatibility_flags = optional(list(string))
    env_vars            = optional(map(string))
  })
  default = null

  validation {
    condition     = var.pages_project == null || can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.pages_project.name))
    error_message = "Pages project name must be lowercase alphanumeric with hyphens, starting and ending with alphanumeric."
  }

  validation {
    condition = var.pages_project == null || var.pages_project.github_repo == null || contains(
      ["all", "none", "custom"],
      var.pages_project.github_repo.preview_deployment_setting
    )
    error_message = "Preview deployment setting must be one of: all, none, custom."
  }
}

#------------------------------------------------------------------------------
# Custom Hostnames Configuration
#------------------------------------------------------------------------------

variable "custom_hostnames" {
  description = "Custom hostnames for multi-tenant SaaS custom domains"
  type = map(object({
    hostname     = string
    ssl_method   = optional(string, "http")
    ssl_type     = optional(string, "dv")
    wait_for_ssl = optional(bool, false)

    ssl_settings = optional(object({
      min_tls_version = optional(string, "1.2")
      ciphers         = optional(list(string))
      early_hints     = optional(string, "off")
      http2           = optional(string, "on")
      tls_1_3         = optional(string, "on")
    }))

    metadata = optional(map(string))
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.custom_hostnames : contains(["http", "txt", "email"], v.ssl_method)
    ])
    error_message = "SSL method must be one of: http, txt, email."
  }

  validation {
    condition = alltrue([
      for k, v in var.custom_hostnames : contains(["dv"], v.ssl_type)
    ])
    error_message = "SSL type must be: dv (Domain Validation)."
  }

  validation {
    condition = alltrue([
      for k, v in var.custom_hostnames : v.ssl_settings == null || contains(
        ["1.0", "1.1", "1.2", "1.3"],
        v.ssl_settings.min_tls_version
      )
    ])
    error_message = "Minimum TLS version must be one of: 1.0, 1.1, 1.2, 1.3."
  }
}

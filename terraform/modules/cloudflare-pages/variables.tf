variable "account_id" {
  description = "Cloudflare account ID"
  type        = string

  validation {
    condition     = can(regex("^[a-f0-9]{32}$", var.account_id))
    error_message = "Account ID must be a 32-character hexadecimal string."
  }
}

variable "project_name" {
  description = "Name for the Cloudflare Pages project (used in *.pages.dev URL)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$", var.project_name))
    error_message = "Project name must be lowercase alphanumeric with hyphens, 2-63 characters, start/end with alphanumeric."
  }
}

variable "production_branch" {
  description = "Git branch used for production deployments"
  type        = string
  default     = "main"
}

#------------------------------------------------------------------------------
# Build Configuration
#------------------------------------------------------------------------------

variable "build_command" {
  description = "Command to build the site (e.g., 'hugo --minify')"
  type        = string
  default     = "hugo --minify"
}

variable "build_output_directory" {
  description = "Directory containing the built site (e.g., 'public')"
  type        = string
  default     = "public"
}

variable "build_root_directory" {
  description = "Root directory for the build (empty string for repository root)"
  type        = string
  default     = ""
}

#------------------------------------------------------------------------------
# Environment Variables
#------------------------------------------------------------------------------

variable "enable_deployment_configs" {
  description = "Enable deployment configuration with environment variables"
  type        = bool
  default     = false
}

variable "preview_environment_variables" {
  description = "Environment variables for preview deployments"
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "production_environment_variables" {
  description = "Environment variables for production deployments"
  type        = map(string)
  default     = {}
  sensitive   = true
}

#------------------------------------------------------------------------------
# Custom Domain Configuration
#------------------------------------------------------------------------------

variable "custom_domain" {
  description = "Primary custom domain for the Pages project (e.g., 'staticshop.io')"
  type        = string
  default     = null

  validation {
    condition = var.custom_domain == null || can(regex(
      "^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$",
      var.custom_domain
    ))
    error_message = "Custom domain must be a valid domain name."
  }
}

variable "www_redirect_domain" {
  description = "WWW subdomain for redirect to primary domain (e.g., 'www.staticshop.io')"
  type        = string
  default     = null

  validation {
    condition = var.www_redirect_domain == null || can(regex(
      "^www\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$",
      var.www_redirect_domain
    ))
    error_message = "WWW redirect domain must start with 'www.' and be a valid domain name."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod). Used for tagging and comments."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

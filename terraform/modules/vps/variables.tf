variable "name" {
  description = "Name of the VPS instance"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.name)) && length(var.name) >= 3 && length(var.name) <= 63
    error_message = "Name must be 3-63 characters, start with a letter, end with alphanumeric, and contain only lowercase letters, numbers, and hyphens."
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

variable "provider_type" {
  description = "Cloud provider to use (scaleway or ovh)"
  type        = string
  default     = "scaleway"

  validation {
    condition     = contains(["scaleway", "ovh"], var.provider_type)
    error_message = "Provider type must be one of: scaleway, ovh."
  }
}

variable "instance_type" {
  description = "Instance type/size for the VPS (Scaleway: DEV1-S, DEV1-M, GP1-S, etc. OVH: s1-2, s1-4, b2-7, etc.)"
  type        = string
}

variable "region" {
  description = "Region where the VPS will be deployed"
  type        = string
}

variable "zone" {
  description = "Zone within the region (Scaleway only, e.g., fr-par-1)"
  type        = string
  default     = null
}

variable "image" {
  description = "OS image to use for the VPS (default: Ubuntu 22.04)"
  type        = string
  default     = "ubuntu_jammy"
}

variable "ssh_public_key" {
  description = "SSH public key content to configure for access"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^ssh-(rsa|ed25519|ecdsa)", var.ssh_public_key))
    error_message = "SSH public key must be a valid SSH public key starting with ssh-rsa, ssh-ed25519, or ssh-ecdsa."
  }
}

variable "ssh_key_name" {
  description = "Name for the SSH key resource"
  type        = string
  default     = null
}

variable "ssh_user" {
  description = "SSH username for the VPS (default: root)"
  type        = string
  default     = "root"
}

variable "ssh_allowed_ips" {
  description = "List of CIDR blocks allowed to SSH (leave empty for all). Use /32 for single IPs."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for ip in var.ssh_allowed_ips : can(cidrhost(ip, 0))
    ])
    error_message = "Each SSH allowed IP must be a valid CIDR block (e.g., 10.0.0.1/32 for single IP, 10.0.0.0/24 for range)."
  }
}

variable "enable_cloudflare_only" {
  description = "Restrict HTTP/HTTPS access to Cloudflare IPs only"
  type        = bool
  default     = true
}

variable "additional_http_allowed_ips" {
  description = "Additional IP addresses/CIDR blocks allowed for HTTP/HTTPS beyond Cloudflare"
  type        = list(string)
  default     = []
}

variable "install_docker" {
  description = "Install Docker on the VPS"
  type        = bool
  default     = true
}

variable "install_docker_compose" {
  description = "Install Docker Compose on the VPS"
  type        = bool
  default     = true
}

variable "docker_compose_version" {
  description = "Docker Compose version to install. NOTE: Consider overriding this to get security patches as the default may become outdated."
  type        = string
  default     = "v2.24.0"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.docker_compose_version))
    error_message = "Docker Compose version must be in format v#.#.# (e.g., v2.24.0)."
  }
}

variable "enable_ipv6" {
  description = "Enable IPv6 on the VPS"
  type        = bool
  default     = true
}

variable "additional_security_group_rules" {
  description = "Additional security group rules to apply"
  type = list(object({
    direction   = string
    protocol    = string
    port        = optional(number)
    port_range  = optional(string)
    ip_range    = optional(string)
    description = optional(string)
  }))
  default = []

  validation {
    condition = alltrue([
      for rule in var.additional_security_group_rules : contains(["inbound", "outbound"], rule.direction)
    ])
    error_message = "Each rule's direction must be 'inbound' or 'outbound'."
  }
}

variable "tags" {
  description = "Tags to apply to the VPS instance"
  type        = map(string)
  default     = {}
}

#------------------------------------------------------------------------------
# OVH-specific variables
#------------------------------------------------------------------------------

variable "enable_ovh_firewall" {
  description = "Enable nftables-based firewall for OVH instances (provides equivalent protection to Scaleway security groups)"
  type        = bool
  default     = true
}

variable "ovh_cloud_project_id" {
  description = "OVH Cloud Project ID (required for OVH provider)"
  type        = string
  default     = null
}

variable "ovh_image_id" {
  description = "OVH image ID for the instance (required for OVH provider)"
  type        = string
  default     = null
}

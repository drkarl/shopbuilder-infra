variable "zone_name" {
  description = "DNS zone name (domain), e.g., 'staticshop.io'"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.zone_name))
    error_message = "Zone name must be a valid domain name (e.g., 'example.com' or 'sub.example.com')."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod). Reserved for future use in record comments or tags."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

#------------------------------------------------------------------------------
# API Record Configuration
#------------------------------------------------------------------------------

variable "api_record" {
  description = "API subdomain record configuration (A/AAAA record pointing to VPS)"
  type = object({
    subdomain  = string
    value      = string
    type       = optional(string, "A")
    ttl        = optional(number, 300)
    proxied    = optional(bool, true)
    ipv6_value = optional(string)
    comment    = optional(string)
  })
  default = null

  validation {
    condition     = var.api_record == null || contains(["A", "AAAA"], var.api_record.type)
    error_message = "API record type must be 'A' or 'AAAA'."
  }

  validation {
    condition     = var.api_record == null || var.api_record.ttl >= 1 && var.api_record.ttl <= 86400
    error_message = "TTL must be between 1 and 86400 seconds."
  }

  validation {
    condition = var.api_record == null || (
      var.api_record.type == "A" ? can(regex("^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$", var.api_record.value)) :
      var.api_record.type == "AAAA" ? can(regex("^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$", var.api_record.value)) :
      true
    )
    error_message = "API record value must be a valid IPv4 address when type is 'A', or a valid IPv6 address when type is 'AAAA'."
  }

  validation {
    condition = var.api_record == null || var.api_record.ipv6_value == null || (
      can(regex("^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$", var.api_record.ipv6_value))
    )
    error_message = "API record ipv6_value must be a valid IPv6 address."
  }
}

#------------------------------------------------------------------------------
# Frontend Record Configuration
#------------------------------------------------------------------------------

variable "frontend_record" {
  description = "Frontend subdomain record configuration (CNAME to Cloudflare Pages or other hosting)"
  type = object({
    subdomain = string
    value     = string
    ttl       = optional(number, 300)
    proxied   = optional(bool, true)
    comment   = optional(string)
  })
  default = null

  validation {
    condition     = var.frontend_record == null || var.frontend_record.ttl >= 1 && var.frontend_record.ttl <= 86400
    error_message = "TTL must be between 1 and 86400 seconds."
  }

  validation {
    condition = var.frontend_record == null || (
      can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$", var.frontend_record.value))
    )
    error_message = "Frontend record value must be a valid hostname for CNAME."
  }
}

#------------------------------------------------------------------------------
# Marketing/Root Record Configuration
#------------------------------------------------------------------------------

variable "marketing_record" {
  description = "Marketing/root domain record configuration (CNAME with flattening at root, or A record)"
  type = object({
    subdomain = string
    value     = string
    type      = optional(string, "CNAME")
    ttl       = optional(number, 300)
    proxied   = optional(bool, true)
    comment   = optional(string)
  })
  default = null

  validation {
    condition     = var.marketing_record == null || contains(["A", "AAAA", "CNAME"], var.marketing_record.type)
    error_message = "Marketing record type must be 'A', 'AAAA', or 'CNAME'."
  }

  validation {
    condition     = var.marketing_record == null || var.marketing_record.ttl >= 1 && var.marketing_record.ttl <= 86400
    error_message = "TTL must be between 1 and 86400 seconds."
  }
}

#------------------------------------------------------------------------------
# Custom Records
#------------------------------------------------------------------------------

variable "custom_records" {
  description = "Additional custom DNS records"
  type = list(object({
    name     = string
    value    = string
    type     = string
    ttl      = optional(number, 300)
    proxied  = optional(bool, false)
    priority = optional(number)
    comment  = optional(string)
  }))
  default = []

  validation {
    condition = alltrue([
      for record in var.custom_records : contains(
        ["A", "AAAA", "CNAME", "TXT", "MX", "SRV", "CAA", "NS", "PTR"],
        record.type
      )
    ])
    error_message = "Custom record type must be one of: A, AAAA, CNAME, TXT, MX, SRV, CAA, NS, PTR."
  }

  validation {
    condition = alltrue([
      for record in var.custom_records : record.ttl >= 1 && record.ttl <= 86400
    ])
    error_message = "All custom record TTLs must be between 1 and 86400 seconds."
  }

  validation {
    condition = alltrue([
      for record in var.custom_records : !(record.type == "MX" || record.type == "SRV") || record.priority != null
    ])
    error_message = "MX and SRV records must have a priority value set."
  }
}


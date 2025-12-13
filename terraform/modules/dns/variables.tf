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
# Email DNS Records (Resend/Transactional Email)
#------------------------------------------------------------------------------

variable "email_records" {
  description = "Email DNS records for domain verification (SPF, DKIM, DMARC). These records are required for transactional email services like Resend."
  type = object({
    enabled = optional(bool, false)
    # Domain to send from (typically the zone_name or a subdomain like mail.example.com)
    sending_domain = optional(string)
    # SPF record - specifies authorized mail servers
    spf = optional(object({
      value = string # e.g., "v=spf1 include:_spf.resend.com ~all"
      ttl   = optional(number, 300)
    }))
    # DKIM records - for email authentication/signing (Resend typically provides multiple)
    dkim = optional(list(object({
      selector = string # e.g., "resend._domainkey" or custom selector
      value    = string # The DKIM public key value
      ttl      = optional(number, 300)
    })), [])
    # DMARC record - policy for handling authentication failures
    dmarc = optional(object({
      policy       = optional(string, "none") # none, quarantine, reject
      rua          = optional(string)         # Aggregate report email (mailto:...)
      ruf          = optional(string)         # Forensic report email (mailto:...)
      pct          = optional(number, 100)    # Percentage of messages to apply policy
      ttl          = optional(number, 300)
      custom_value = optional(string) # Override with custom DMARC value
    }))
  })
  default = null

  validation {
    condition = var.email_records == null || var.email_records.enabled == false || (
      var.email_records.spf != null
    )
    error_message = "SPF record is required when email records are enabled."
  }

  validation {
    condition = var.email_records == null || var.email_records.dmarc == null || (
      contains(["none", "quarantine", "reject"], var.email_records.dmarc.policy)
    )
    error_message = "DMARC policy must be one of: none, quarantine, reject."
  }

  validation {
    condition = var.email_records == null || var.email_records.dmarc == null || var.email_records.dmarc.pct == null || (
      var.email_records.dmarc.pct >= 0 && var.email_records.dmarc.pct <= 100
    )
    error_message = "DMARC percentage must be between 0 and 100."
  }

  validation {
    condition = (
      var.email_records == null ||
      var.email_records.spf == null ||
      var.email_records.spf.ttl == null ||
      (var.email_records.spf.ttl >= 1 && var.email_records.spf.ttl <= 86400)
    )
    error_message = "SPF TTL must be between 1 and 86400 seconds."
  }

  validation {
    condition = (
      var.email_records == null ||
      var.email_records.dkim == null ||
      length([
        for d in var.email_records.dkim : d
        if d.ttl != null && (d.ttl < 1 || d.ttl > 86400)
      ]) == 0
    )
    error_message = "Each DKIM TTL must be between 1 and 86400 seconds."
  }

  validation {
    condition = (
      var.email_records == null ||
      var.email_records.dmarc == null ||
      var.email_records.dmarc.ttl == null ||
      (var.email_records.dmarc.ttl >= 1 && var.email_records.dmarc.ttl <= 86400)
    )
    error_message = "DMARC TTL must be between 1 and 86400 seconds."
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

# DNS Module
# This module manages DNS records using Cloudflare

terraform {
  required_version = ">= 1.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

#------------------------------------------------------------------------------
# Data Sources
#------------------------------------------------------------------------------

# Look up the zone ID from the zone name
data "cloudflare_zone" "this" {
  name = var.zone_name
}

#------------------------------------------------------------------------------
# API Record (A/AAAA)
# Points to VPS IP address, proxied through Cloudflare
#------------------------------------------------------------------------------

resource "cloudflare_record" "api" {
  count = var.api_record != null ? 1 : 0

  zone_id = data.cloudflare_zone.this.id
  name    = var.api_record.subdomain
  content = var.api_record.value
  type    = var.api_record.type
  ttl     = var.api_record.proxied ? 1 : var.api_record.ttl
  proxied = var.api_record.proxied

  comment = var.api_record.comment
}

# API AAAA record (IPv6) - optional
resource "cloudflare_record" "api_ipv6" {
  count = var.api_record != null && var.api_record.ipv6_value != null ? 1 : 0

  zone_id = data.cloudflare_zone.this.id
  name    = var.api_record.subdomain
  content = var.api_record.ipv6_value
  type    = "AAAA"
  ttl     = var.api_record.proxied ? 1 : var.api_record.ttl
  proxied = var.api_record.proxied

  comment = var.api_record.comment != null ? "${var.api_record.comment} (IPv6)" : "IPv6 record"
}

#------------------------------------------------------------------------------
# Frontend Record (CNAME)
# Points to Cloudflare Pages or other hosting
#------------------------------------------------------------------------------

resource "cloudflare_record" "frontend" {
  count = var.frontend_record != null ? 1 : 0

  zone_id = data.cloudflare_zone.this.id
  name    = var.frontend_record.subdomain
  content = var.frontend_record.value
  type    = "CNAME"
  ttl     = var.frontend_record.proxied ? 1 : var.frontend_record.ttl
  proxied = var.frontend_record.proxied

  comment = var.frontend_record.comment
}

#------------------------------------------------------------------------------
# Marketing/Root Record (CNAME flattening at root or A record)
# Points to Cloudflare Pages for the main domain
#------------------------------------------------------------------------------

resource "cloudflare_record" "marketing" {
  count = var.marketing_record != null ? 1 : 0

  zone_id = data.cloudflare_zone.this.id
  name    = var.marketing_record.subdomain
  content = var.marketing_record.value
  type    = var.marketing_record.type
  ttl     = var.marketing_record.proxied ? 1 : var.marketing_record.ttl
  proxied = var.marketing_record.proxied

  comment = var.marketing_record.comment
}

#------------------------------------------------------------------------------
# Email DNS Records (SPF, DKIM, DMARC)
# Required for transactional email services like Resend
#------------------------------------------------------------------------------

locals {
  email_enabled     = var.email_records != null && var.email_records.enabled
  email_domain_name = local.email_enabled && var.email_records.sending_domain != null ? var.email_records.sending_domain : "@"

  # Build DMARC value from components or use custom value
  dmarc_value = local.email_enabled && var.email_records.dmarc != null ? (
    var.email_records.dmarc.custom_value != null ? var.email_records.dmarc.custom_value : join("; ", compact([
      "v=DMARC1",
      "p=${var.email_records.dmarc.policy}",
      var.email_records.dmarc.pct != null && var.email_records.dmarc.pct != 100 ? "pct=${var.email_records.dmarc.pct}" : null,
      var.email_records.dmarc.rua != null ? "rua=${var.email_records.dmarc.rua}" : null,
      var.email_records.dmarc.ruf != null ? "ruf=${var.email_records.dmarc.ruf}" : null
    ]))
  ) : null
}

# SPF Record - Specifies authorized mail servers
resource "cloudflare_record" "email_spf" {
  count = local.email_enabled && var.email_records.spf != null ? 1 : 0

  zone_id = data.cloudflare_zone.this.id
  name    = local.email_domain_name
  content = var.email_records.spf.value
  type    = "TXT"
  ttl     = var.email_records.spf.ttl
  proxied = false

  comment = "SPF record for email authentication"
}

# DKIM Records - For email signing/authentication
resource "cloudflare_record" "email_dkim" {
  for_each = local.email_enabled ? {
    for idx, dkim in var.email_records.dkim : dkim.selector => dkim
  } : {}

  zone_id = data.cloudflare_zone.this.id
  name    = each.value.selector
  content = each.value.value
  type    = "TXT"
  ttl     = each.value.ttl
  proxied = false

  comment = "DKIM record for email signing (${each.value.selector})"
}

# DMARC Record - Policy for handling authentication failures
resource "cloudflare_record" "email_dmarc" {
  count = local.email_enabled && var.email_records.dmarc != null ? 1 : 0

  zone_id = data.cloudflare_zone.this.id
  name    = "_dmarc"
  content = local.dmarc_value
  type    = "TXT"
  ttl     = var.email_records.dmarc.ttl
  proxied = false

  comment = "DMARC policy record"
}

#------------------------------------------------------------------------------
# Additional Custom Records
# Flexible support for any additional DNS records
#------------------------------------------------------------------------------

resource "cloudflare_record" "custom" {
  for_each = { for idx, record in var.custom_records : "${record.name}-${record.type}-${idx}" => record }

  zone_id  = data.cloudflare_zone.this.id
  name     = each.value.name
  content  = each.value.value
  type     = each.value.type
  ttl      = each.value.proxied ? 1 : each.value.ttl
  proxied  = each.value.proxied
  priority = each.value.priority

  comment = each.value.comment
}

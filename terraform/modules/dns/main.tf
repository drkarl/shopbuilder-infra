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

output "zone_id" {
  description = "ID of the Cloudflare DNS zone"
  value       = data.cloudflare_zone.this.id
}

output "zone_name" {
  description = "Name of the DNS zone"
  value       = data.cloudflare_zone.this.name
}

output "name_servers" {
  description = "Name servers for the DNS zone"
  value       = data.cloudflare_zone.this.name_servers
}

#------------------------------------------------------------------------------
# API Record Outputs
#------------------------------------------------------------------------------

output "api_record_id" {
  description = "ID of the API DNS record"
  value       = length(cloudflare_record.api) > 0 ? cloudflare_record.api[0].id : null
}

output "api_record_hostname" {
  description = "Hostname of the API DNS record"
  value       = length(cloudflare_record.api) > 0 ? cloudflare_record.api[0].hostname : null
}

output "api_ipv6_record_id" {
  description = "ID of the API IPv6 DNS record"
  value       = length(cloudflare_record.api_ipv6) > 0 ? cloudflare_record.api_ipv6[0].id : null
}

#------------------------------------------------------------------------------
# Frontend Record Outputs
#------------------------------------------------------------------------------

output "frontend_record_id" {
  description = "ID of the frontend DNS record"
  value       = length(cloudflare_record.frontend) > 0 ? cloudflare_record.frontend[0].id : null
}

output "frontend_record_hostname" {
  description = "Hostname of the frontend DNS record"
  value       = length(cloudflare_record.frontend) > 0 ? cloudflare_record.frontend[0].hostname : null
}

#------------------------------------------------------------------------------
# Marketing Record Outputs
#------------------------------------------------------------------------------

output "marketing_record_id" {
  description = "ID of the marketing/root DNS record"
  value       = length(cloudflare_record.marketing) > 0 ? cloudflare_record.marketing[0].id : null
}

output "marketing_record_hostname" {
  description = "Hostname of the marketing/root DNS record"
  value       = length(cloudflare_record.marketing) > 0 ? cloudflare_record.marketing[0].hostname : null
}

#------------------------------------------------------------------------------
# Custom Record Outputs
#------------------------------------------------------------------------------

output "custom_record_ids" {
  description = "Map of custom DNS record names to their IDs"
  value       = { for name, record in cloudflare_record.custom : name => record.id }
}

output "custom_record_hostnames" {
  description = "Map of custom DNS record names to their hostnames"
  value       = { for name, record in cloudflare_record.custom : name => record.hostname }
}

#------------------------------------------------------------------------------
# Email Record Outputs
#------------------------------------------------------------------------------

output "email_spf_record_id" {
  description = "ID of the SPF DNS record"
  value       = length(cloudflare_record.email_spf) > 0 ? cloudflare_record.email_spf[0].id : null
}

output "email_dkim_record_ids" {
  description = "Map of DKIM selector names to their record IDs"
  value       = { for selector, record in cloudflare_record.email_dkim : selector => record.id }
}

output "email_dmarc_record_id" {
  description = "ID of the DMARC DNS record"
  value       = length(cloudflare_record.email_dmarc) > 0 ? cloudflare_record.email_dmarc[0].id : null
}

output "email_records_summary" {
  description = "Summary of email DNS records for verification"
  value = {
    enabled = local.email_enabled
    spf = length(cloudflare_record.email_spf) > 0 ? {
      hostname = cloudflare_record.email_spf[0].hostname
      value    = cloudflare_record.email_spf[0].content
    } : null
    dkim = { for selector, record in cloudflare_record.email_dkim : selector => {
      hostname = record.hostname
      value    = record.content
    } }
    dmarc = length(cloudflare_record.email_dmarc) > 0 ? {
      hostname = cloudflare_record.email_dmarc[0].hostname
      value    = cloudflare_record.email_dmarc[0].content
    } : null
  }
}

#------------------------------------------------------------------------------
# All Records Summary
#------------------------------------------------------------------------------

output "all_record_ids" {
  description = "All DNS record IDs managed by this module"
  value = {
    api       = length(cloudflare_record.api) > 0 ? cloudflare_record.api[0].id : null
    api_ipv6  = length(cloudflare_record.api_ipv6) > 0 ? cloudflare_record.api_ipv6[0].id : null
    frontend  = length(cloudflare_record.frontend) > 0 ? cloudflare_record.frontend[0].id : null
    marketing = length(cloudflare_record.marketing) > 0 ? cloudflare_record.marketing[0].id : null
    custom    = { for name, record in cloudflare_record.custom : name => record.id }
    email = {
      spf   = length(cloudflare_record.email_spf) > 0 ? cloudflare_record.email_spf[0].id : null
      dkim  = { for selector, record in cloudflare_record.email_dkim : selector => record.id }
      dmarc = length(cloudflare_record.email_dmarc) > 0 ? cloudflare_record.email_dmarc[0].id : null
    }
  }
}

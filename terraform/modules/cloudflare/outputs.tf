#------------------------------------------------------------------------------
# R2 Bucket Outputs
#------------------------------------------------------------------------------

output "r2_bucket_name" {
  description = "Name of the created R2 bucket"
  value       = var.r2_bucket != null ? cloudflare_r2_bucket.this[0].name : null
}

output "r2_bucket_id" {
  description = "ID of the created R2 bucket"
  value       = var.r2_bucket != null ? cloudflare_r2_bucket.this[0].id : null
}

output "r2_bucket_location" {
  description = "Location of the R2 bucket"
  value       = var.r2_bucket != null ? cloudflare_r2_bucket.this[0].location : null
}

output "r2_endpoint" {
  description = "S3-compatible endpoint URL for R2 bucket"
  value       = "https://${var.account_id}.r2.cloudflarestorage.com"
}

#------------------------------------------------------------------------------
# Pages Project Outputs
#------------------------------------------------------------------------------

output "pages_project_name" {
  description = "Name of the Pages project"
  value       = var.pages_project != null ? cloudflare_pages_project.this[0].name : null
}

output "pages_project_id" {
  description = "ID of the Pages project"
  value       = var.pages_project != null ? cloudflare_pages_project.this[0].id : null
}

output "pages_subdomain" {
  description = "Default subdomain for the Pages project"
  value       = var.pages_project != null ? cloudflare_pages_project.this[0].subdomain : null
}

output "pages_domains" {
  description = "All domains associated with the Pages project"
  value       = var.pages_project != null ? cloudflare_pages_project.this[0].domains : null
}

output "pages_custom_domain" {
  description = "Custom domain attached to the Pages project"
  value       = var.pages_project != null && var.pages_project.custom_domain != null ? cloudflare_pages_domain.this[0].domain : null
}

output "pages_custom_domain_status" {
  description = "Status of the custom domain"
  value       = var.pages_project != null && var.pages_project.custom_domain != null ? cloudflare_pages_domain.this[0].status : null
}

#------------------------------------------------------------------------------
# Custom Hostnames Outputs
#------------------------------------------------------------------------------

output "custom_hostnames" {
  description = "Map of custom hostname configurations"
  value = {
    for k, v in cloudflare_custom_hostname.this : k => {
      id       = v.id
      hostname = v.hostname
      status   = v.status
      ssl = {
        status = v.ssl[0].status
        method = v.ssl[0].method
        type   = v.ssl[0].type
      }
    }
  }
}

output "custom_hostname_ids" {
  description = "Map of custom hostname IDs"
  value = {
    for k, v in cloudflare_custom_hostname.this : k => v.id
  }
}

#------------------------------------------------------------------------------
# Zone Information (for API operations)
#------------------------------------------------------------------------------

output "zone_id" {
  description = "Zone ID for API operations (Cache Purge, Custom Hostnames)"
  value       = var.zone_name != null ? data.cloudflare_zone.this[0].id : null
}

output "zone_name" {
  description = "Zone name"
  value       = var.zone_name
}

#------------------------------------------------------------------------------
# API Endpoint Information
#------------------------------------------------------------------------------

output "api_endpoints" {
  description = "Cloudflare API endpoints for programmatic access"
  value = {
    # R2 S3-compatible endpoint
    r2_endpoint = "https://${var.account_id}.r2.cloudflarestorage.com"

    # Cache Purge endpoint (requires zone_id)
    cache_purge = var.zone_name != null ? "https://api.cloudflare.com/client/v4/zones/${data.cloudflare_zone.this[0].id}/purge_cache" : null

    # Custom Hostnames endpoint (requires zone_id)
    custom_hostnames = var.zone_name != null ? "https://api.cloudflare.com/client/v4/zones/${data.cloudflare_zone.this[0].id}/custom_hostnames" : null

    # Pages Direct Upload (requires account_id and project name)
    pages_upload = var.pages_project != null ? "https://api.cloudflare.com/client/v4/accounts/${var.account_id}/pages/projects/${var.pages_project.name}/deployments" : null
  }
}

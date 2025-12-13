# Production Environment Outputs

output "environment" {
  description = "Current environment name"
  value       = local.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

#------------------------------------------------------------------------------
# Marketing Site Outputs (Cloudflare Pages)
#------------------------------------------------------------------------------

output "marketing_site_url" {
  description = "URL of the marketing site on Cloudflare Pages"
  value       = module.marketing_site.pages_url
}

output "marketing_site_custom_domain" {
  description = "Custom domain for the marketing site"
  value       = module.marketing_site.custom_domain
}

output "marketing_site_deployment_info" {
  description = "Deployment information for CI/CD"
  value       = module.marketing_site.deployment_info
}

#------------------------------------------------------------------------------
# DNS Outputs
#------------------------------------------------------------------------------

output "dns_zone_id" {
  description = "Cloudflare DNS zone ID"
  value       = module.dns.zone_id
}

output "dns_name_servers" {
  description = "Name servers for the DNS zone"
  value       = module.dns.name_servers
}

# Add additional module outputs here as infrastructure grows
# Example:
# output "vps_public_ip" {
#   description = "Public IP of the VPS instance"
#   value       = module.vps.public_ip
# }

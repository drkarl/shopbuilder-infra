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

#------------------------------------------------------------------------------
# Neon PostgreSQL Outputs
#------------------------------------------------------------------------------

output "neon_project_id" {
  description = "Neon project identifier"
  value       = module.neon_database.project_id
}

output "neon_database_host" {
  description = "Direct database hostname (for Flyway migrations)"
  value       = module.neon_database.database_host
}

output "neon_database_host_pooler" {
  description = "Pooled database hostname (for application)"
  value       = module.neon_database.database_host_pooler
}

output "neon_connection_uri" {
  description = "Direct connection URI (for Flyway migrations)"
  value       = module.neon_database.connection_uri
  sensitive   = true
}

output "neon_connection_uri_pooler" {
  description = "Pooled connection URI (for application)"
  value       = module.neon_database.connection_uri_pooler
  sensitive   = true
}

output "neon_connection_info" {
  description = "Database connection information summary"
  value       = module.neon_database.connection_info
}

#------------------------------------------------------------------------------
# Upstash Redis Outputs
#------------------------------------------------------------------------------

output "redis_endpoint" {
  description = "Redis endpoint hostname"
  value       = module.redis.endpoint
}

output "redis_port" {
  description = "Redis port number"
  value       = module.redis.port
}

output "redis_url" {
  description = "Full Redis connection URL (sensitive - add to SOPS secrets)"
  value       = module.redis.redis_url
  sensitive   = true
}

output "redis_connection_info" {
  description = "Non-sensitive Redis connection summary"
  value       = module.redis.connection_info
}

# Add additional module outputs here as infrastructure grows
# Example:
# output "vps_public_ip" {
#   description = "Public IP of the VPS instance"
#   value       = module.vps.public_ip
# }

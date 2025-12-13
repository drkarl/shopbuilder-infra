# Staging Environment Outputs

output "environment" {
  description = "Current environment name"
  value       = local.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
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

# Add additional module outputs here as infrastructure grows
# Example:
# output "vps_public_ip" {
#   description = "Public IP of the VPS instance"
#   value       = module.vps.public_ip
# }

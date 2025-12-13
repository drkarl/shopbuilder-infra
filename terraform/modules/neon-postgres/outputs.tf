#------------------------------------------------------------------------------
# Project Information
#------------------------------------------------------------------------------

output "project_id" {
  description = "Neon project identifier"
  value       = neon_project.this.id
}

output "project_name" {
  description = "Name of the Neon project"
  value       = neon_project.this.name
}

output "region_id" {
  description = "Neon region where the project is deployed"
  value       = neon_project.this.region_id
}

#------------------------------------------------------------------------------
# Branch and Endpoint Information
#------------------------------------------------------------------------------

output "default_branch_id" {
  description = "ID of the default branch"
  value       = neon_project.this.default_branch_id
}

output "default_endpoint_id" {
  description = "ID of the default compute endpoint"
  value       = neon_project.this.default_endpoint_id
}

#------------------------------------------------------------------------------
# Database Connection - Direct (for migrations/admin)
#------------------------------------------------------------------------------

output "database_host" {
  description = "Direct database hostname (use for Flyway migrations and admin tasks)"
  value       = neon_project.this.database_host
}

output "connection_uri" {
  description = "Direct connection URI with credentials (use for Flyway migrations)"
  value       = neon_project.this.connection_uri
  sensitive   = true
}

#------------------------------------------------------------------------------
# Database Connection - Pooled (for application)
#------------------------------------------------------------------------------

output "database_host_pooler" {
  description = "Pooled database hostname (use for application connections)"
  value       = neon_project.this.database_host_pooler
}

output "connection_uri_pooler" {
  description = "Pooled connection URI with credentials (use for application)"
  value       = neon_project.this.connection_uri_pooler
  sensitive   = true
}

#------------------------------------------------------------------------------
# Database Credentials (for reference)
#------------------------------------------------------------------------------

output "database_name" {
  description = "Default database name"
  value       = neon_project.this.database_name
}

output "database_user" {
  description = "Default database role/user"
  value       = neon_project.this.database_user
}

output "database_password" {
  description = "Database password for the default role"
  value       = neon_project.this.database_password
  sensitive   = true
}

#------------------------------------------------------------------------------
# Connection Information Summary
#------------------------------------------------------------------------------

output "connection_info" {
  description = "Summary of connection information for documentation"
  value = {
    project_id          = neon_project.this.id
    region              = neon_project.this.region_id
    database            = neon_project.this.database_name
    user                = neon_project.this.database_user
    direct_host         = neon_project.this.database_host
    pooler_host         = neon_project.this.database_host_pooler
    pg_version          = var.pg_version
    min_compute_units   = var.autoscaling_min_cu
    max_compute_units   = var.autoscaling_max_cu
    suspend_timeout_sec = var.suspend_timeout_seconds
  }
}

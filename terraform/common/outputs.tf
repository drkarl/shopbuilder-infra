# Common Outputs
# These outputs are available from the root module of each environment

output "environment" {
  description = "Current environment name"
  value       = var.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

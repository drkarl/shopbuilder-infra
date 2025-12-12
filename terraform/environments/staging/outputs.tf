# Staging Environment Outputs

output "environment" {
  description = "Current environment name"
  value       = local.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

# Add module outputs here as infrastructure grows
# Example:
# output "vps_public_ip" {
#   description = "Public IP of the VPS instance"
#   value       = module.vps.public_ip
# }

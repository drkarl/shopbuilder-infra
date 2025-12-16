# CI Environment Outputs
#
# EPHEMERAL RUNNER WORKFLOW
# After 'terraform apply', use these outputs to:
#   1. SSH in and register the runner (if not auto-registered)
#   2. Run your CI jobs
#   3. 'terraform destroy' when done to stop billing

output "runner_ip" {
  description = "Runner public IPv4 address"
  value       = module.github_runner.ipv4_address
}

output "runner_ipv6" {
  description = "Runner public IPv6 address"
  value       = module.github_runner.ipv6_address
}

output "server_type" {
  description = "Actual Hetzner server type deployed"
  value       = module.github_runner.server_type
}

output "server_size" {
  description = "Server size preset used"
  value       = var.server_size
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = module.github_runner.ssh_command
}

output "ssh_config_entry" {
  description = "Add to ~/.ssh/config"
  value       = module.github_runner.ssh_config_entry
}

output "setup_instructions" {
  description = "Post-deployment instructions"
  value       = module.github_runner.runner_install_instructions
}

#------------------------------------------------------------------------------
# Ephemeral Workflow Helpers
#------------------------------------------------------------------------------

output "hourly_cost" {
  description = "Estimated hourly cost for this server"
  value       = var.server_size == "small" ? "~€0.015/hr (cpx32)" : var.server_size == "burst" ? "~€0.028/hr (cpx42)" : "varies (custom)"
}

output "cost_reminder" {
  description = "Cost savings reminder"
  value       = <<-EOT
    REMINDER: This runner uses Hetzner hourly billing.
    - Server running = charged per hour (rounded up)
    - Server DESTROYED = no charge

    When done with CI:
      terraform destroy

    To restart later:
      terraform apply
  EOT
}

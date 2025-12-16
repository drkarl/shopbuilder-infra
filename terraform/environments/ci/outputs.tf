# CI Environment Outputs

output "runner_ip" {
  description = "Runner public IPv4 address"
  value       = module.github_runner.ipv4_address
}

output "runner_ipv6" {
  description = "Runner public IPv6 address"
  value       = module.github_runner.ipv6_address
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

# Hetzner GitHub Runner Module - Outputs

output "server_id" {
  description = "Hetzner server ID"
  value       = hcloud_server.runner.id
}

output "server_name" {
  description = "Server name"
  value       = hcloud_server.runner.name
}

output "ipv4_address" {
  description = "Public IPv4 address"
  value       = hcloud_server.runner.ipv4_address
}

output "ipv6_address" {
  description = "Public IPv6 address"
  value       = hcloud_server.runner.ipv6_address
}

output "status" {
  description = "Server status"
  value       = hcloud_server.runner.status
}

output "server_type" {
  description = "Server type"
  value       = hcloud_server.runner.server_type
}

output "location" {
  description = "Datacenter location"
  value       = hcloud_server.runner.location
}

output "ssh_command" {
  description = "SSH command to connect to the runner"
  value       = "ssh -p ${var.ssh_port} ${var.runner_user}@${hcloud_server.runner.ipv4_address}"
}

output "ssh_config_entry" {
  description = "SSH config entry for ~/.ssh/config"
  value       = <<-EOT
# Add to ~/.ssh/config
Host ${var.name}
    HostName ${hcloud_server.runner.ipv4_address}
    User ${var.runner_user}
    Port ${var.ssh_port}
    IdentityFile ~/.ssh/hetzner_id_ed25519
EOT
}

output "runner_install_instructions" {
  description = "Instructions to install the GitHub Actions runner"
  value       = <<-EOT
To complete setup:
1. SSH to the server: ssh -p ${var.ssh_port} ${var.runner_user}@${hcloud_server.runner.ipv4_address}
2. Get a runner token from: https://github.com/<owner>/<repo>/settings/actions/runners/new
3. Run: ./install-runner.sh <TOKEN>
4. When prompted, enter the repository URL
EOT
}

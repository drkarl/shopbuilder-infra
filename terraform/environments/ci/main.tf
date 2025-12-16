# CI Environment
# GitHub Actions self-hosted runners infrastructure

terraform {
  required_version = ">= 1.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
  }
}

# Hetzner Cloud Provider
# Set HCLOUD_TOKEN environment variable for authentication
provider "hcloud" {}

locals {
  environment = "ci"
  common_labels = {
    environment = local.environment
    project     = var.project_name
    managed_by  = "terraform"
  }
}

#------------------------------------------------------------------------------
# GitHub Actions Runner
#------------------------------------------------------------------------------

module "github_runner" {
  source = "../../modules/hetzner-github-runner"

  name        = var.runner_name
  server_type = local.effective_server_type
  location    = var.location
  image       = var.image

  ssh_public_key = var.ssh_public_key
  ssh_key_name   = var.ssh_key_name

  runner_user   = var.runner_user
  runner_labels = var.runner_labels

  # Security
  ssh_port          = var.ssh_port
  ssh_allowed_ips   = var.ssh_allowed_ips
  fail2ban_maxretry = var.fail2ban_maxretry
  fail2ban_bantime  = var.fail2ban_bantime

  # Software
  install_docker = var.install_docker
  install_java   = var.install_java
  java_version   = var.java_version
  extra_packages = var.extra_packages

  # Cleanup
  enable_cleanup_timer         = var.enable_cleanup_timer
  cleanup_docker_after_hours   = var.cleanup_docker_after_hours
  cleanup_workspace_after_days = var.cleanup_workspace_after_days

  # GitHub auto-registration (optional)
  auto_register_runner = var.auto_register_runner
  github_token         = var.github_token
  github_owner         = var.github_owner
  github_repository    = var.github_repository

  labels = local.common_labels
}

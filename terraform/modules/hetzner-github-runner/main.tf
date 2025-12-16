# Hetzner GitHub Runner Module
# Creates a hardened VM for GitHub Actions self-hosted runners

terraform {
  required_version = ">= 1.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

#------------------------------------------------------------------------------
# GitHub Provider (for auto-registration)
#------------------------------------------------------------------------------

provider "github" {
  token = var.github_token
  owner = var.github_owner
}

#------------------------------------------------------------------------------
# Locals
#------------------------------------------------------------------------------

locals {
  common_labels = merge(var.labels, {
    managed_by = "terraform"
    purpose    = "github-runner"
  })

  # SSH allowed IPs for firewall rules
  ssh_source_ips = length(var.ssh_allowed_ips) > 0 ? var.ssh_allowed_ips : ["0.0.0.0/0", "::/0"]

  # Runner labels as comma-separated string
  runner_labels_str = join(",", var.runner_labels)

  # Runner name (default to server name)
  effective_runner_name = var.runner_name != "" ? var.runner_name : var.name

  # GitHub repo URL for runner config
  github_repo_url = var.github_owner != "" && var.github_repository != "" ? "https://github.com/${var.github_owner}/${var.github_repository}" : ""
}

#------------------------------------------------------------------------------
# GitHub Runner Registration Token (optional)
#------------------------------------------------------------------------------

data "github_actions_registration_token" "runner" {
  count      = var.auto_register_runner ? 1 : 0
  repository = var.github_repository
}

#------------------------------------------------------------------------------
# Hetzner Resources
#------------------------------------------------------------------------------

# SSH Key
resource "hcloud_ssh_key" "runner" {
  name       = var.ssh_key_name
  public_key = var.ssh_public_key
}

# Firewall
resource "hcloud_firewall" "runner" {
  name = "${var.name}-firewall"

  # SSH access
  dynamic "rule" {
    for_each = local.ssh_source_ips
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = tostring(var.ssh_port)
      source_ips = [rule.value]
    }
  }

  # Allow ICMP (ping)
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Allow all outbound
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "1-65535"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "1-65535"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "icmp"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  labels = local.common_labels
}

# Server
resource "hcloud_server" "runner" {
  name        = var.name
  server_type = var.server_type
  location    = var.location
  image       = var.image

  ssh_keys = [hcloud_ssh_key.runner.id]

  firewall_ids = [hcloud_firewall.runner.id]

  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    runner_user                  = var.runner_user
    ssh_public_key               = var.ssh_public_key
    ssh_port                     = var.ssh_port
    fail2ban_maxretry            = var.fail2ban_maxretry
    fail2ban_bantime             = var.fail2ban_bantime
    runner_labels                = local.runner_labels_str
    install_java                 = var.install_java
    java_version                 = var.java_version
    install_docker               = var.install_docker
    enable_cleanup_timer         = var.enable_cleanup_timer
    cleanup_docker_after_hours   = var.cleanup_docker_after_hours
    cleanup_workspace_after_days = var.cleanup_workspace_after_days
    extra_packages               = var.extra_packages
    # Auto-registration variables
    auto_register_runner = var.auto_register_runner
    runner_token         = var.auto_register_runner ? data.github_actions_registration_token.runner[0].token : ""
    github_repo_url      = local.github_repo_url
    runner_name          = local.effective_runner_name
  })

  labels = local.common_labels

  lifecycle {
    prevent_destroy = false
  }
}

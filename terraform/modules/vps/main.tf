# VPS Module
# This module manages VPS instances across different cloud providers (Scaleway and OVH)

terraform {
  required_version = ">= 1.0"
}

locals {
  ssh_key_name = var.ssh_key_name != null ? var.ssh_key_name : "${var.name}-ssh-key"

  # Cloudflare IPv4 ranges (https://www.cloudflare.com/ips-v4)
  cloudflare_ipv4_ranges = [
    "173.245.48.0/20",
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "141.101.64.0/18",
    "108.162.192.0/18",
    "190.93.240.0/20",
    "188.114.96.0/20",
    "197.234.240.0/22",
    "198.41.128.0/17",
    "162.158.0.0/15",
    "104.16.0.0/13",
    "104.24.0.0/14",
    "172.64.0.0/13",
    "131.0.72.0/22",
  ]

  # Cloudflare IPv6 ranges (https://www.cloudflare.com/ips-v6)
  cloudflare_ipv6_ranges = [
    "2400:cb00::/32",
    "2606:4700::/32",
    "2803:f800::/32",
    "2405:b500::/32",
    "2405:8100::/32",
    "2a06:98c0::/29",
    "2c0f:f248::/32",
  ]

  # Combined HTTP allowed IPs
  http_allowed_ips = var.enable_cloudflare_only ? concat(
    local.cloudflare_ipv4_ranges,
    var.enable_ipv6 ? local.cloudflare_ipv6_ranges : [],
    var.additional_http_allowed_ips
  ) : ["0.0.0.0/0"]

  # SSH allowed IPs - if empty, allow all
  ssh_allowed_ips = length(var.ssh_allowed_ips) > 0 ? var.ssh_allowed_ips : ["0.0.0.0/0"]

  # Common tags with provider-specific format
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Module      = "vps"
  })

  # User data script for Docker installation
  docker_install_script = var.install_docker ? <<-EOF
    #!/bin/bash
    set -e

    # Update system
    apt-get update
    apt-get upgrade -y

    # Install prerequisites
    apt-get install -y \
      apt-transport-https \
      ca-certificates \
      curl \
      gnupg \
      lsb-release

    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Enable and start Docker
    systemctl enable docker
    systemctl start docker

    ${var.install_docker_compose ? local.docker_compose_install_script : ""}
  EOF

  docker_compose_install_script = <<-EOF
    # Install Docker Compose standalone (in addition to plugin)
    DOCKER_COMPOSE_VERSION="${var.docker_compose_version}"
    curl -SL "https://github.com/docker/compose/releases/download/$${DOCKER_COMPOSE_VERSION}/docker-compose-linux-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
  EOF

  # Final user data - empty string if no Docker install needed
  user_data = var.install_docker ? local.docker_install_script : ""
}

#------------------------------------------------------------------------------
# Scaleway Resources
#------------------------------------------------------------------------------

# Scaleway SSH Key
resource "scaleway_iam_ssh_key" "this" {
  count = var.provider_type == "scaleway" ? 1 : 0

  name       = local.ssh_key_name
  public_key = var.ssh_public_key
}

# Scaleway Security Group
resource "scaleway_instance_security_group" "this" {
  count = var.provider_type == "scaleway" ? 1 : 0

  name                    = "${var.name}-sg"
  inbound_default_policy  = "drop"
  outbound_default_policy = "accept"

  # SSH access rules
  dynamic "inbound_rule" {
    for_each = local.ssh_allowed_ips
    content {
      action   = "accept"
      protocol = "TCP"
      port     = 22
      ip_range = inbound_rule.value
    }
  }

  # HTTP access rules (Cloudflare IPs or all)
  dynamic "inbound_rule" {
    for_each = local.http_allowed_ips
    content {
      action   = "accept"
      protocol = "TCP"
      port     = 80
      ip_range = inbound_rule.value
    }
  }

  # HTTPS access rules (Cloudflare IPs or all)
  dynamic "inbound_rule" {
    for_each = local.http_allowed_ips
    content {
      action   = "accept"
      protocol = "TCP"
      port     = 443
      ip_range = inbound_rule.value
    }
  }

  # Additional custom rules
  dynamic "inbound_rule" {
    for_each = [for rule in var.additional_security_group_rules : rule if rule.direction == "inbound"]
    content {
      action   = "accept"
      protocol = upper(inbound_rule.value.protocol)
      port     = inbound_rule.value.port
      ip_range = inbound_rule.value.ip_range != null ? inbound_rule.value.ip_range : "0.0.0.0/0"
    }
  }

  dynamic "outbound_rule" {
    for_each = [for rule in var.additional_security_group_rules : rule if rule.direction == "outbound"]
    content {
      action   = "accept"
      protocol = upper(outbound_rule.value.protocol)
      port     = outbound_rule.value.port
      ip_range = outbound_rule.value.ip_range != null ? outbound_rule.value.ip_range : "0.0.0.0/0"
    }
  }
}

# Scaleway Instance
resource "scaleway_instance_server" "this" {
  count = var.provider_type == "scaleway" ? 1 : 0

  name  = var.name
  type  = var.instance_type
  image = var.image
  zone  = var.zone

  ip_id             = scaleway_instance_ip.this[0].id
  security_group_id = scaleway_instance_security_group.this[0].id

  enable_ipv6 = var.enable_ipv6

  user_data = {
    cloud-init = local.user_data
  }

  tags = [for k, v in local.common_tags : "${k}=${v}"]

  depends_on = [scaleway_iam_ssh_key.this]
}

# Scaleway Public IP
resource "scaleway_instance_ip" "this" {
  count = var.provider_type == "scaleway" ? 1 : 0

  zone = var.zone
}

#------------------------------------------------------------------------------
# OVH Resources
# Note: OVH VPS uses the dedicated_server or cloud_project resources
# Here we implement using OVH Cloud (Public Cloud) instances
#------------------------------------------------------------------------------

# OVH Account-level SSH Key
resource "ovh_me_ssh_key" "this" {
  count = var.provider_type == "ovh" ? 1 : 0

  key_name = local.ssh_key_name
  key      = var.ssh_public_key
}

# OVH Cloud Project Instance
resource "ovh_cloud_project_instance" "this" {
  count = var.provider_type == "ovh" ? 1 : 0

  service_name = var.ovh_cloud_project_id
  name         = var.name
  flavor_name  = var.instance_type
  region       = var.region

  # Use the SSH key
  ssh_key = ovh_me_ssh_key.this[0].key_name

  # Boot from image
  boot_from {
    image_id = var.ovh_image_id
  }

  network {
    public = true
  }

  depends_on = [ovh_me_ssh_key.this]
}

# OVH instances don't have built-in security groups like Scaleway
# Firewall rules must be configured via cloud-init/user-data using iptables/nftables
# or using OVH's vRack/Private Network features

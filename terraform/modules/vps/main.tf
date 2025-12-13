# VPS Module
# This module manages VPS instances across different cloud providers (Scaleway and OVH)

terraform {
  required_version = ">= 1.0"

  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.0"
    }
    ovh = {
      source  = "ovh/ovh"
      version = ">= 0.40"
    }
  }
}

locals {
  ssh_key_name = var.ssh_key_name != null ? var.ssh_key_name : "${var.name}-ssh-key"

  # Cloudflare IPv4 ranges (https://www.cloudflare.com/ips-v4)
  # NOTE: These IP ranges should be periodically reviewed as Cloudflare occasionally
  # adds new ranges. Check https://www.cloudflare.com/ips/ for updates.
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

  # Docker Compose installation script with checksum verification
  docker_compose_install_script = <<-EOF
# Install Docker Compose standalone (in addition to plugin) with checksum verification
DOCKER_COMPOSE_VERSION="${var.docker_compose_version}"
ARCH=$(uname -m)
COMPOSE_URL="https://github.com/docker/compose/releases/download/$${DOCKER_COMPOSE_VERSION}/docker-compose-linux-$${ARCH}"
CHECKSUM_URL="https://github.com/docker/compose/releases/download/$${DOCKER_COMPOSE_VERSION}/checksums.txt"

# Download binary and checksums
curl -SL "$${COMPOSE_URL}" -o /tmp/docker-compose
curl -SL "$${CHECKSUM_URL}" -o /tmp/checksums.txt

# Verify checksum
EXPECTED_CHECKSUM=$(grep "docker-compose-linux-$${ARCH}$" /tmp/checksums.txt | awk '{print $1}')
ACTUAL_CHECKSUM=$(sha256sum /tmp/docker-compose | awk '{print $1}')

if [ "$${EXPECTED_CHECKSUM}" != "$${ACTUAL_CHECKSUM}" ]; then
  echo "ERROR: Docker Compose checksum verification failed!"
  echo "Expected: $${EXPECTED_CHECKSUM}"
  echo "Actual: $${ACTUAL_CHECKSUM}"
  rm -f /tmp/docker-compose /tmp/checksums.txt
  exit 1
fi

echo "Docker Compose checksum verified successfully"
mv /tmp/docker-compose /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
rm -f /tmp/checksums.txt
EOF

  # Docker compose script inclusion (empty if not installing)
  docker_compose_section = var.install_docker_compose ? local.docker_compose_install_script : ""

  # User data script for Docker installation
  docker_install_script_content = <<-EOF
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

${local.docker_compose_section}
EOF

  # Final user data - empty string if no Docker install needed
  user_data = var.install_docker ? local.docker_install_script_content : ""

  # SSH rules for nftables (OVH firewall)
  nftables_ssh_rules = join("\n    ", [for ip in local.ssh_allowed_ips : "ip saddr ${ip} tcp dport 22 accept"])

  # HTTP/HTTPS rules for nftables (OVH firewall)
  nftables_http_rules_v4 = var.enable_cloudflare_only ? join("\n    ", concat(
    [for ip in local.cloudflare_ipv4_ranges : "ip saddr ${ip} tcp dport 80 accept"],
    [for ip in local.cloudflare_ipv4_ranges : "ip saddr ${ip} tcp dport 443 accept"],
    [for ip in var.additional_http_allowed_ips : "ip saddr ${ip} tcp dport 80 accept"],
    [for ip in var.additional_http_allowed_ips : "ip saddr ${ip} tcp dport 443 accept"]
  )) : "tcp dport 80 accept\n    tcp dport 443 accept"

  nftables_http_rules_v6 = var.enable_cloudflare_only && var.enable_ipv6 ? join("\n    ", concat(
    [for ip in local.cloudflare_ipv6_ranges : "ip6 saddr ${ip} tcp dport 80 accept"],
    [for ip in local.cloudflare_ipv6_ranges : "ip6 saddr ${ip} tcp dport 443 accept"]
  )) : ""

  # OVH firewall script using nftables (since OVH doesn't have native security groups)
  # This provides equivalent protection to Scaleway's security groups
  ovh_firewall_script_content = <<-EOF
#!/bin/bash
set -e

# Install nftables if not present
apt-get update
apt-get install -y nftables

# Create nftables configuration
cat > /etc/nftables.conf << 'NFTCONF'
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;

    # Allow established/related connections
    ct state established,related accept

    # Allow loopback
    iif lo accept

    # SSH rules
    ${local.nftables_ssh_rules}

    # HTTP/HTTPS rules (Cloudflare IPs or all)
    ${local.nftables_http_rules_v4}
    ${local.nftables_http_rules_v6}

    # ICMP for ping
    ip protocol icmp accept
    ip6 nexthdr icmpv6 accept
  }

  chain forward {
    type filter hook forward priority 0; policy drop;
  }

  chain output {
    type filter hook output priority 0; policy accept;
  }
}
NFTCONF

# Enable and start nftables
systemctl enable nftables
systemctl restart nftables

echo "nftables firewall configured successfully"
EOF

  # OVH firewall script (empty if disabled)
  ovh_firewall_script = var.enable_ovh_firewall ? local.ovh_firewall_script_content : ""

  # Combined user data for OVH (firewall + docker if enabled)
  ovh_user_data = join("\n", compact([
    local.ovh_firewall_script,
    local.user_data
  ]))
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

  # Additional custom rules (with single port)
  dynamic "inbound_rule" {
    for_each = [for rule in var.additional_security_group_rules : rule if rule.direction == "inbound" && rule.port != null]
    content {
      action   = "accept"
      protocol = upper(inbound_rule.value.protocol)
      port     = inbound_rule.value.port
      ip_range = inbound_rule.value.ip_range != null ? inbound_rule.value.ip_range : "0.0.0.0/0"
    }
  }

  # Additional custom rules (with port range)
  dynamic "inbound_rule" {
    for_each = [for rule in var.additional_security_group_rules : rule if rule.direction == "inbound" && rule.port == null && rule.port_range != null]
    content {
      action     = "accept"
      protocol   = upper(inbound_rule.value.protocol)
      port_range = inbound_rule.value.port_range
      ip_range   = inbound_rule.value.ip_range != null ? inbound_rule.value.ip_range : "0.0.0.0/0"
    }
  }

  dynamic "outbound_rule" {
    for_each = [for rule in var.additional_security_group_rules : rule if rule.direction == "outbound" && rule.port != null]
    content {
      action   = "accept"
      protocol = upper(outbound_rule.value.protocol)
      port     = outbound_rule.value.port
      ip_range = outbound_rule.value.ip_range != null ? outbound_rule.value.ip_range : "0.0.0.0/0"
    }
  }

  dynamic "outbound_rule" {
    for_each = [for rule in var.additional_security_group_rules : rule if rule.direction == "outbound" && rule.port == null && rule.port_range != null]
    content {
      action     = "accept"
      protocol   = upper(outbound_rule.value.protocol)
      port_range = outbound_rule.value.port_range
      ip_range   = outbound_rule.value.ip_range != null ? outbound_rule.value.ip_range : "0.0.0.0/0"
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

  user_data = {
    cloud-init = local.user_data
  }

  tags = [for k, v in local.common_tags : "${k}=${v}"]

  depends_on = [scaleway_iam_ssh_key.this]

  lifecycle {
    precondition {
      condition     = var.zone != null
      error_message = "The 'zone' variable is required when provider_type is 'scaleway'."
    }
  }
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

  # Cloud-init user data (includes firewall setup and Docker installation)
  user_data = local.ovh_user_data

  depends_on = [ovh_me_ssh_key.this]

  lifecycle {
    precondition {
      condition     = var.ovh_cloud_project_id != null
      error_message = "The 'ovh_cloud_project_id' variable is required when provider_type is 'ovh'."
    }
    precondition {
      condition     = var.ovh_image_id != null
      error_message = "The 'ovh_image_id' variable is required when provider_type is 'ovh'."
    }
  }
}

# Note: OVH instances don't have built-in security groups like Scaleway
# The nftables firewall is configured via cloud-init when enable_ovh_firewall = true

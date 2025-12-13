# Development Environment
# Main configuration for the dev environment

terraform {
  required_version = ">= 1.0"

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "~> 0.40"
    }

    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.0"
    }
  }
}

# OVH Provider
provider "ovh" {
  endpoint = var.ovh_endpoint
}

# Scaleway Provider
provider "scaleway" {
  region = var.scaleway_region
  zone   = var.scaleway_zone
}

locals {
  environment = "dev"
  common_tags = merge(var.common_tags, {
    Environment = local.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  })
}

# Add module calls here as infrastructure grows
# Example VPS deployment:
# module "vps" {
#   source = "../../modules/vps"
#
#   name          = "${var.project_name}-${local.environment}"
#   environment   = local.environment
#   provider_type = "scaleway"
#
#   instance_type = var.vps_instance_type
#   region        = var.scaleway_region
#   zone          = var.scaleway_zone
#   image         = "ubuntu_jammy"
#
#   ssh_public_key = var.ssh_public_key
#   ssh_user       = "root"
#
#   # Restrict SSH to specific IPs in production
#   ssh_allowed_ips = []
#
#   # HTTP/HTTPS only from Cloudflare
#   enable_cloudflare_only = true
#
#   # Docker installation
#   install_docker         = true
#   install_docker_compose = true
#
#   tags = local.common_tags
# }

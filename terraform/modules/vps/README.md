# VPS Module

Reusable Terraform module for provisioning EU-based VPS instances on Scaleway or OVH.

## Features

- **Multi-provider support**: Deploy to Scaleway or OVH Cloud
- **SSH key management**: Automatic SSH key upload and configuration
- **Security-first firewall**: HTTP/HTTPS restricted to Cloudflare IPs by default
- **Configurable SSH access**: Restrict SSH to specific IP addresses
- **Docker pre-installed**: Automatic Docker and Docker Compose installation via cloud-init
- **IPv6 support**: Optional IPv6 connectivity

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| scaleway | ~> 2.0 (if using Scaleway) |
| ovh | ~> 0.40 (if using OVH) |

## Usage

### Scaleway Example

```hcl
module "vps" {
  source = "../../modules/vps"

  name          = "myapp-prod"
  environment   = "prod"
  provider_type = "scaleway"

  instance_type = "DEV1-S"
  region        = "fr-par"
  zone          = "fr-par-1"
  image         = "ubuntu_jammy"

  ssh_public_key = file("~/.ssh/id_ed25519.pub")
  ssh_user       = "root"

  # Restrict SSH to specific IPs
  ssh_allowed_ips = ["203.0.113.0/24"]

  # HTTP/HTTPS only from Cloudflare (default)
  enable_cloudflare_only = true

  # Docker installation
  install_docker         = true
  install_docker_compose = true
  docker_compose_version = "v2.24.0"

  tags = {
    Project = "myapp"
    Team    = "platform"
  }
}

output "vps_ip" {
  value = module.vps.ip_address
}

output "ssh_command" {
  value = module.vps.ssh_connection_string
}
```

### OVH Example

```hcl
module "vps" {
  source = "../../modules/vps"

  name          = "myapp-prod"
  environment   = "prod"
  provider_type = "ovh"

  instance_type = "s1-2"
  region        = "GRA11"

  # OVH-specific configuration
  ovh_cloud_project_id = "your-project-id"
  ovh_image_id         = "your-ubuntu-image-id"

  ssh_public_key = file("~/.ssh/id_ed25519.pub")
  ssh_user       = "ubuntu"

  # Docker installation
  install_docker         = true
  install_docker_compose = true

  tags = {
    Project = "myapp"
  }
}
```

### Minimal Example

```hcl
module "vps" {
  source = "../../modules/vps"

  name          = "myapp-dev"
  environment   = "dev"
  instance_type = "DEV1-S"
  region        = "fr-par"
  zone          = "fr-par-1"

  ssh_public_key = file("~/.ssh/id_ed25519.pub")
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | Name of the VPS instance | `string` | n/a | yes |
| environment | Environment name (dev, staging, prod) | `string` | n/a | yes |
| instance_type | Instance type/size for the VPS | `string` | n/a | yes |
| region | Region where the VPS will be deployed | `string` | n/a | yes |
| ssh_public_key | SSH public key content to configure for access | `string` | n/a | yes |
| provider_type | Cloud provider to use (scaleway or ovh) | `string` | `"scaleway"` | no |
| zone | Zone within the region (Scaleway only) | `string` | `null` | no |
| image | OS image to use for the VPS | `string` | `"ubuntu_jammy"` | no |
| ssh_key_name | Name for the SSH key resource | `string` | `null` | no |
| ssh_user | SSH username for the VPS | `string` | `"root"` | no |
| ssh_allowed_ips | List of IP addresses/CIDR blocks allowed to SSH | `list(string)` | `[]` | no |
| enable_cloudflare_only | Restrict HTTP/HTTPS access to Cloudflare IPs only | `bool` | `true` | no |
| additional_http_allowed_ips | Additional IP addresses for HTTP/HTTPS beyond Cloudflare | `list(string)` | `[]` | no |
| install_docker | Install Docker on the VPS | `bool` | `true` | no |
| install_docker_compose | Install Docker Compose on the VPS | `bool` | `true` | no |
| docker_compose_version | Docker Compose version to install | `string` | `"v2.24.0"` | no |
| enable_ipv6 | Enable IPv6 on the VPS | `bool` | `true` | no |
| additional_security_group_rules | Additional security group rules to apply | `list(object)` | `[]` | no |
| tags | Tags to apply to the VPS instance | `map(string)` | `{}` | no |
| ovh_cloud_project_id | OVH Cloud Project ID (required for OVH provider) | `string` | `null` | no |
| ovh_image_id | OVH image ID for the instance (required for OVH provider) | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | ID of the VPS instance |
| public_ip | Public IP address of the VPS instance |
| private_ip | Private IP address of the VPS instance |
| ip_address | Public IP address of the VPS instance (alias) |
| ssh_connection_string | SSH connection string to connect to the VPS |
| ssh_key_id | ID of the SSH key resource |
| security_group_id | ID of the security group (Scaleway only) |
| provider_type | Cloud provider type used for this VPS |
| instance_name | Name of the VPS instance |

## Security Configuration

### Cloudflare IP Restriction

By default, this module restricts HTTP (80) and HTTPS (443) traffic to Cloudflare IP ranges only. This ensures that all web traffic flows through Cloudflare's proxy, providing:

- DDoS protection
- Web Application Firewall (WAF)
- SSL/TLS termination
- Caching

The following Cloudflare IPv4 ranges are allowed:
- 173.245.48.0/20
- 103.21.244.0/22
- 103.22.200.0/22
- 103.31.4.0/22
- 141.101.64.0/18
- 108.162.192.0/18
- 190.93.240.0/20
- 188.114.96.0/20
- 197.234.240.0/22
- 198.41.128.0/17
- 162.158.0.0/15
- 104.16.0.0/13
- 104.24.0.0/14
- 172.64.0.0/13
- 131.0.72.0/22

To disable Cloudflare-only restriction:
```hcl
enable_cloudflare_only = false
```

### SSH Access Restriction

By default, SSH is open to all IPs. To restrict SSH access:

```hcl
ssh_allowed_ips = [
  "203.0.113.10/32",    # Office IP
  "198.51.100.0/24",    # VPN range
]
```

### Custom Firewall Rules

Add custom firewall rules using the `additional_security_group_rules` variable:

```hcl
additional_security_group_rules = [
  {
    direction   = "inbound"
    protocol    = "tcp"
    port        = 8080
    ip_range    = "10.0.0.0/8"
    description = "Internal API access"
  }
]
```

## Docker Installation

Docker and Docker Compose are installed automatically via cloud-init during instance provisioning. The installation includes:

- Docker CE (latest stable)
- Docker CLI
- containerd.io
- Docker Buildx plugin
- Docker Compose plugin
- Docker Compose standalone binary

To skip Docker installation:
```hcl
install_docker         = false
install_docker_compose = false
```

## Provider-Specific Notes

### Scaleway

- Security groups are fully managed with inbound default policy set to "drop"
- All outbound traffic is allowed by default
- IPv6 is enabled by default
- SSH keys are managed via Scaleway IAM

### OVH

- OVH Cloud instances don't have native security groups like Scaleway
- Firewall rules should be managed via cloud-init (iptables/nftables) or OVH Network features
- Requires `ovh_cloud_project_id` and `ovh_image_id` variables
- SSH keys are managed at the OVH account level

## Instance Types

### Scaleway

| Type | vCPU | RAM | Storage |
|------|------|-----|---------|
| DEV1-S | 2 | 2GB | 20GB |
| DEV1-M | 3 | 4GB | 40GB |
| DEV1-L | 4 | 8GB | 80GB |
| GP1-XS | 4 | 16GB | 150GB |
| GP1-S | 8 | 32GB | 300GB |

### OVH

| Type | vCPU | RAM | Storage |
|------|------|-----|---------|
| s1-2 | 1 | 2GB | 10GB |
| s1-4 | 1 | 4GB | 20GB |
| s1-8 | 2 | 8GB | 40GB |
| b2-7 | 2 | 7GB | 50GB |
| b2-15 | 4 | 15GB | 100GB |

## Environment Variables

### Scaleway

```bash
export SCW_ACCESS_KEY="your-access-key"
export SCW_SECRET_KEY="your-secret-key"
export SCW_DEFAULT_PROJECT_ID="your-project-id"
```

### OVH

```bash
export OVH_ENDPOINT="ovh-eu"
export OVH_APPLICATION_KEY="your-app-key"
export OVH_APPLICATION_SECRET="your-app-secret"
export OVH_CONSUMER_KEY="your-consumer-key"
```

## License

This module is part of the shopbuilder-infra project.

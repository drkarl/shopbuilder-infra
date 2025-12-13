# DNS Module

Reusable Terraform module for managing DNS records using Cloudflare.

## Features

- **Cloudflare DNS management**: Create and manage DNS records via Cloudflare API
- **Proxy configuration**: Support for proxied (orange cloud) and DNS-only records
- **A/AAAA records**: API subdomain pointing to VPS IP addresses
- **CNAME records**: Frontend subdomain pointing to Cloudflare Pages or other hosting
- **Root domain support**: Marketing site with CNAME flattening at apex
- **IPv6 support**: Optional AAAA records for dual-stack configurations
- **Custom records**: Flexible support for additional DNS records (MX, TXT, SRV, etc.)
- **Input validation**: Comprehensive validation for domain names, IP addresses, and TTL values

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| cloudflare | ~> 4.0 |

## Usage

### Complete Example (StaticShop.io)

```hcl
module "dns" {
  source = "../../modules/dns"

  zone_name   = "staticshop.io"
  environment = "prod"

  # API: api.staticshop.io -> VPS IP (proxied through Cloudflare)
  api_record = {
    subdomain  = "api"
    value      = "203.0.113.10"  # VPS IPv4 address
    type       = "A"
    proxied    = true
    ipv6_value = "2001:db8::1"  # Optional IPv6
    comment    = "API server"
  }

  # Frontend: app.staticshop.io -> CNAME to Cloudflare Pages
  frontend_record = {
    subdomain = "app"
    value     = "staticshop-app.pages.dev"
    proxied   = true
    comment   = "Frontend application"
  }

  # Marketing: staticshop.io -> Cloudflare Pages (root domain)
  marketing_record = {
    subdomain = "@"
    value     = "staticshop-marketing.pages.dev"
    type      = "CNAME"
    proxied   = true
    comment   = "Marketing website"
  }
}

output "api_dns" {
  value = module.dns.api_record_hostname
}
```

### API-Only Example

```hcl
module "dns" {
  source = "../../modules/dns"

  zone_name   = "example.com"
  environment = "prod"

  api_record = {
    subdomain = "api"
    value     = module.vps.public_ip
    proxied   = true
  }
}
```

### With Custom Records

```hcl
module "dns" {
  source = "../../modules/dns"

  zone_name   = "example.com"
  environment = "prod"

  api_record = {
    subdomain = "api"
    value     = "203.0.113.10"
  }

  # Additional records
  custom_records = [
    {
      name     = "mail"
      value    = "mail.example.com"
      type     = "MX"
      priority = 10
      proxied  = false
    },
    {
      name    = "@"
      value   = "v=spf1 include:_spf.google.com ~all"
      type    = "TXT"
      proxied = false
    },
    {
      name    = "_dmarc"
      value   = "v=DMARC1; p=reject; rua=mailto:dmarc@example.com"
      type    = "TXT"
      proxied = false
    }
  ]
}
```

### DNS-Only (No Proxy)

```hcl
module "dns" {
  source = "../../modules/dns"

  zone_name   = "example.com"
  environment = "dev"

  api_record = {
    subdomain = "api"
    value     = "203.0.113.10"
    proxied   = false
    ttl       = 300
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| zone_name | DNS zone name (domain) | `string` | n/a | yes |
| environment | Environment name (dev, staging, prod) | `string` | n/a | yes |
| api_record | API subdomain record configuration | `object` | `null` | no |
| frontend_record | Frontend subdomain record configuration | `object` | `null` | no |
| marketing_record | Marketing/root domain record configuration | `object` | `null` | no |
| custom_records | Additional custom DNS records | `list(object)` | `[]` | no |

### api_record Object

| Attribute | Description | Type | Default |
|-----------|-------------|------|---------|
| subdomain | Subdomain name (e.g., "api") | `string` | - |
| value | IPv4 address for the A record | `string` | - |
| type | Record type ("A" or "AAAA") | `string` | `"A"` |
| ttl | Time to live in seconds (1 = automatic when proxied) | `number` | `300` |
| proxied | Enable Cloudflare proxy (orange cloud) | `bool` | `true` |
| ipv6_value | Optional IPv6 address for additional AAAA record | `string` | `null` |
| comment | Record comment | `string` | `null` |

### frontend_record Object

| Attribute | Description | Type | Default |
|-----------|-------------|------|---------|
| subdomain | Subdomain name (e.g., "app") | `string` | - |
| value | Target hostname for CNAME | `string` | - |
| ttl | Time to live in seconds | `number` | `300` |
| proxied | Enable Cloudflare proxy | `bool` | `true` |
| comment | Record comment | `string` | `null` |

### marketing_record Object

| Attribute | Description | Type | Default |
|-----------|-------------|------|---------|
| subdomain | Subdomain name ("@" for root) | `string` | - |
| value | Target value | `string` | - |
| type | Record type ("A", "AAAA", or "CNAME") | `string` | `"CNAME"` |
| ttl | Time to live in seconds | `number` | `300` |
| proxied | Enable Cloudflare proxy | `bool` | `true` |
| comment | Record comment | `string` | `null` |

### custom_records Object

| Attribute | Description | Type | Default |
|-----------|-------------|------|---------|
| name | Record name | `string` | - |
| value | Record value | `string` | - |
| type | Record type (A, AAAA, CNAME, TXT, MX, SRV, CAA, NS, PTR) | `string` | - |
| ttl | Time to live in seconds | `number` | `300` |
| proxied | Enable Cloudflare proxy | `bool` | `false` |
| priority | Priority (required for MX records) | `number` | `null` |
| comment | Record comment | `string` | `null` |

## Outputs

| Name | Description |
|------|-------------|
| zone_id | ID of the Cloudflare DNS zone |
| zone_name | Name of the DNS zone |
| name_servers | Name servers for the DNS zone |
| api_record_id | ID of the API DNS record |
| api_record_hostname | Hostname of the API DNS record |
| api_ipv6_record_id | ID of the API IPv6 DNS record |
| frontend_record_id | ID of the frontend DNS record |
| frontend_record_hostname | Hostname of the frontend DNS record |
| marketing_record_id | ID of the marketing/root DNS record |
| marketing_record_hostname | Hostname of the marketing/root DNS record |
| custom_record_ids | Map of custom DNS record names to their IDs |
| custom_record_hostnames | Map of custom DNS record names to their hostnames |
| all_record_ids | All DNS record IDs managed by this module |

## Cloudflare Proxy (Orange Cloud)

When `proxied = true`:
- Traffic flows through Cloudflare's edge network
- DDoS protection is enabled
- WAF rules can be applied
- SSL/TLS is terminated at Cloudflare edge
- Caching is available for static assets
- TTL is automatically set to 1 (automatic)

When `proxied = false` (DNS-only):
- Traffic goes directly to origin
- Custom TTL values are respected
- Useful for non-HTTP services or internal routing

## Environment Variables

The Cloudflare provider requires authentication. Set these environment variables:

```bash
export CLOUDFLARE_API_TOKEN="your-api-token"
# OR
export CLOUDFLARE_EMAIL="your-email"
export CLOUDFLARE_API_KEY="your-global-api-key"  # pragma: allowlist secret
```

## Integration with VPS Module

This DNS module works seamlessly with the VPS module:

```hcl
module "vps" {
  source = "../../modules/vps"

  name          = "api-server"
  environment   = "prod"
  provider_type = "scaleway"
  # ... other VPS configuration
}

module "dns" {
  source = "../../modules/dns"

  zone_name   = "staticshop.io"
  environment = "prod"

  api_record = {
    subdomain = "api"
    value     = module.vps.public_ip
    proxied   = true
  }
}
```

## License

This module is part of the shopbuilder-infra project.

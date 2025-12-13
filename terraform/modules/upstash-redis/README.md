# Upstash Redis Module

Terraform module for provisioning Upstash Redis databases for caching and session management.

## Features

- Serverless Redis with pay-per-request pricing
- TLS encryption enabled by default
- Configurable eviction policies for caching workloads
- Optional auto-scaling
- Global database support with read replicas

## Usage

```hcl
module "redis" {
  source = "../../modules/upstash-redis"

  database_name    = "shopbuilder-prod"
  region           = "eu-west-1"
  environment      = "prod"
  tls_enabled      = true
  eviction_enabled = true
  auto_scale       = false
}
```

## Connection String Format

Upstash Redis uses TLS connections with the `rediss://` protocol (double 's'):

```
rediss://default:[password]@[endpoint]:6379
```

### Spring Boot Configuration

```yaml
spring:
  data:
    redis:
      url: ${UPSTASH_REDIS_URL}
      ssl:
        enabled: true
```

### Lettuce Client (Reactive)

```java
RedisURI redisUri = RedisURI.create(System.getenv("UPSTASH_REDIS_URL"));
RedisClient client = RedisClient.create(redisUri);
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| upstash | ~> 2.0 |

## Providers

| Name | Version |
|------|---------|
| upstash | ~> 2.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| database_name | Name of the Upstash Redis database | `string` | n/a | yes |
| region | Region for the Redis database | `string` | n/a | yes |
| environment | Environment name (dev, staging, prod) | `string` | n/a | yes |
| tls_enabled | Enable TLS encryption (must be true) | `bool` | `true` | no |
| eviction_enabled | Enable key eviction when max size reached | `bool` | `true` | no |
| auto_scale | Auto-upgrade when hitting quotas | `bool` | `false` | no |
| primary_region | Primary region for global databases | `string` | `null` | no |
| read_regions | Read replica regions for global databases | `set(string)` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| database_id | Unique identifier of the Redis database |
| database_name | Name of the Redis database |
| endpoint | Redis endpoint hostname |
| port | Redis port number |
| password | Redis authentication password (sensitive) |
| redis_url | Full Redis connection URL with TLS (sensitive) |
| rest_token | REST API token (sensitive) |
| connection_info | Non-sensitive connection summary |

## Regions

Supported regions:
- `eu-west-1` - Europe (Ireland)
- `eu-central-1` - Europe (Frankfurt)
- `us-east-1` - US East (N. Virginia)
- `us-west-1` - US West (N. California)
- `us-west-2` - US West (Oregon)
- `ap-northeast-1` - Asia Pacific (Tokyo)
- `ap-southeast-1` - Asia Pacific (Singapore)
- `ap-southeast-2` - Asia Pacific (Sydney)
- `sa-east-1` - South America (Sao Paulo)
- `global` - Multi-region (requires primary_region and read_regions)

## Eviction Policy

When `eviction_enabled = true`, Upstash uses an LRU-like eviction policy:
- Keys are evicted when the database reaches its maximum size
- Recommended for caching workloads
- Session data should use explicit TTLs

## Security Notes

- TLS is enforced (cannot be disabled)
- Store `UPSTASH_REDIS_URL` in SOPS-encrypted secrets
- The connection URL contains the password - treat as sensitive
- Use IP allowlists in Upstash Console for additional security

# Redis Configuration

This document describes the Upstash Redis configuration for ShopBuilder's caching and session management.

## Overview

ShopBuilder uses [Upstash Redis](https://upstash.com/) as a serverless Redis solution with the following benefits:

- **Serverless**: No infrastructure to manage
- **Pay-per-request**: Cost-effective for variable workloads
- **Global**: Low-latency access from multiple regions
- **TLS by default**: Secure connections out of the box

## Connection String Format

Upstash Redis uses TLS connections with the `rediss://` protocol (note the double 's'):

```
rediss://default:[password]@[endpoint]:6379
```

### Example

<!-- pragma: allowlist secret -->
```
rediss://default:AxxxXXXX@eu1-xxxxx-xxxxx.upstash.io:6379
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `UPSTASH_REDIS_URL` | Full connection URL for the application |
| `UPSTASH_EMAIL` | Email for Upstash Terraform provider |
| `UPSTASH_API_KEY` | API key for Upstash Terraform provider |

## Spring Boot Configuration

### application.yml

```yaml
spring:
  data:
    redis:
      url: ${UPSTASH_REDIS_URL}
      ssl:
        enabled: true
```

### Reactive Configuration (WebFlux)

```java
@Configuration
public class RedisConfig {

    @Bean
    public ReactiveRedisConnectionFactory reactiveRedisConnectionFactory(
            @Value("${spring.data.redis.url}") String redisUrl) {
        RedisURI redisUri = RedisURI.create(redisUrl);
        LettuceClientConfiguration clientConfig = LettuceClientConfiguration.builder()
            .useSsl()
            .build();
        return new LettuceConnectionFactory(
            new RedisStandaloneConfiguration(redisUri.getHost(), redisUri.getPort()),
            clientConfig
        );
    }
}
```

## Use Cases

### Caching

```java
@Cacheable(value = "products", key = "#productId")
public Mono<Product> getProduct(String productId) {
    return productRepository.findById(productId);
}
```

### Session Management

```yaml
spring:
  session:
    store-type: redis
    redis:
      namespace: shopbuilder:sessions
```

### Rate Limiting

```java
// Using Redis for API rate limiting
@Component
public class RateLimiter {
    private final ReactiveStringRedisTemplate redisTemplate;

    public Mono<Boolean> isAllowed(String clientId, int limit, Duration window) {
        String key = "rate:" + clientId;
        return redisTemplate.opsForValue()
            .increment(key)
            .flatMap(count -> {
                if (count == 1) {
                    return redisTemplate.expire(key, window)
                        .thenReturn(true);
                }
                return Mono.just(count <= limit);
            });
    }
}
```

## Eviction Policy

The Redis databases are configured with eviction enabled (`eviction_enabled = true`). When the database reaches its maximum size:

- Keys are evicted using an LRU-like policy
- Recommended for caching workloads
- Session data should use explicit TTLs to ensure proper expiration

## Upstash Plans and Limits

Upstash offers different pricing tiers. Be aware of these limits when planning your usage:

### Free Tier
- 10,000 commands/day
- 256 MB storage
- Single region
- Suitable for development and testing only

### Pay-as-you-go
- $0.2 per 100K commands
- $0.25 per GB storage/month
- No daily limits
- Recommended for staging/production

### Pro Plans
- Higher throughput
- Multi-region replication
- Dedicated support

For current pricing and limits, see [Upstash Pricing](https://upstash.com/pricing).

## Regions

| Environment | Region | Notes |
|-------------|--------|-------|
| Production | eu-west-1 | Primary region for EU users |
| Staging | eu-west-1 | Matches production for testing |

## Terraform Infrastructure

The Redis infrastructure is managed via Terraform:

```bash
# Initialize
cd terraform/environments/prod
terraform init

# Plan changes
terraform plan

# Apply (requires UPSTASH_EMAIL and UPSTASH_API_KEY)
terraform apply

# Get Redis URL (sensitive output)
terraform output -raw redis_url
```

### Required Variables

Set these before running Terraform:

<!-- pragma: allowlist secret -->
```bash
export TF_VAR_upstash_email="your-email@example.com"
export TF_VAR_upstash_api_key="your-api-key"
```

Or use a `.tfvars` file (do not commit):

```hcl
upstash_email     = "your-email@example.com"
upstash_api_key   = "your-api-key"
```

## Security

### TLS

- All connections use TLS (enforced by the module)
- The `rediss://` protocol indicates TLS is required

### Secrets Management

- Store `UPSTASH_REDIS_URL` in SOPS-encrypted secrets
- The connection URL contains credentials - treat as sensitive
- Never commit unencrypted Redis URLs

### IP Allowlisting (Optional)

For additional security, configure IP allowlists in the Upstash Console:

1. Go to [Upstash Console](https://console.upstash.com/)
2. Select your database
3. Navigate to Security > IP Allowlist
4. Add your application's IP addresses

## Monitoring

### Upstash Console

Monitor usage and performance in the [Upstash Console](https://console.upstash.com/):

- Request count
- Bandwidth usage
- Memory usage
- Latency metrics

### Application Metrics

Export Redis metrics to your monitoring system:

```java
@Bean
public MeterRegistryCustomizer<MeterRegistry> metricsCommonTags() {
    return registry -> {
        // Lettuce metrics are automatically exported when micrometer is present
    };
}
```

## Troubleshooting

### Connection Issues

1. **Verify TLS**: Ensure you're using `rediss://` (not `redis://`)
2. **Check credentials**: Verify the password in the connection URL
3. **Network**: Ensure outbound connections to port 6379 are allowed

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `NOAUTH` | Invalid password | Check UPSTASH_REDIS_URL |
| `Connection refused` | Wrong endpoint | Verify endpoint in URL |
| `SSL handshake failed` | TLS issue | Use `rediss://` protocol |

## Related Documentation

- [Upstash Documentation](https://upstash.com/docs)
- [Spring Data Redis](https://docs.spring.io/spring-data/redis/reference/)
- [Lettuce Reference](https://lettuce.io/core/release/reference/)

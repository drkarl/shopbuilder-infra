# Cloudflare Services Integration

This document describes the Cloudflare services configuration and API usage patterns for the ShopBuilder infrastructure.

## Overview

ShopBuilder uses the following Cloudflare services:

| Service | Purpose |
|---------|---------|
| **DNS** | Domain management and routing |
| **Pages** | Frontend static site hosting |
| **R2** | S3-compatible object storage for assets |
| **Custom Hostnames** | Multi-tenant custom domain support |
| **Cache Purge** | CDN cache invalidation |

## API Token Configuration

### Required Scopes

Create a Cloudflare API token with these permissions:

| Scope | Permission | Resources |
|-------|------------|-----------|
| Zone:DNS:Edit | Edit | All zones or specific zone |
| Account:Cloudflare Pages:Edit | Edit | Account-level |
| Account:R2:Edit | Edit | Account-level |
| Zone:SSL and Certificates:Edit | Edit | All zones or specific zone |
| Zone:Cache Purge:Purge | Purge | All zones or specific zone |

### Creating the Token

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Navigate to **My Profile** > **API Tokens**
3. Click **Create Token**
4. Select **Create Custom Token**
5. Add the required permissions listed above
6. Set appropriate Zone/Account resources
7. Click **Continue to summary** > **Create Token**
8. Copy the token immediately (it won't be shown again)

### Environment Variables

```bash
# Required for Terraform and application
CLOUDFLARE_API_TOKEN=cf_xxxxxxxxxxxxxxxxxxxxxxxxxx
CLOUDFLARE_ACCOUNT_ID=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
CLOUDFLARE_ZONE_ID=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

## R2 Storage

### Overview

R2 provides S3-compatible object storage without egress fees. Use it for:
- User-uploaded assets (images, files)
- Static assets (CSS, JS bundles)
- Backups and exports

### R2 API Tokens

R2 uses separate S3-compatible credentials:

1. Go to **R2** > **Manage R2 API Tokens**
2. Click **Create API Token**
3. Set permissions: **Object Read & Write**
4. Select bucket scope (all or specific)
5. Create and copy credentials

```bash
R2_ACCESS_KEY_ID=xxxxxxxxxxxxxxxxxxxx
R2_SECRET_ACCESS_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### Spring Boot Integration

```java
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;

@Configuration
public class R2Config {

    @Value("${cloudflare.account-id}")
    private String accountId;

    @Value("${r2.access-key-id}")
    private String accessKeyId;

    @Value("${r2.secret-access-key}")
    private String secretAccessKey;

    @Bean
    public S3Client r2Client() {
        return S3Client.builder()
            .endpointOverride(URI.create("https://" + accountId + ".r2.cloudflarestorage.com"))
            .region(Region.of("auto"))
            .credentialsProvider(StaticCredentialsProvider.create(
                AwsBasicCredentials.create(accessKeyId, secretAccessKey)))
            .build();
    }
}
```

### Common Operations

```java
// Upload object
s3Client.putObject(
    PutObjectRequest.builder()
        .bucket("shopbuilder-assets")
        .key("uploads/image.png")
        .contentType("image/png")
        .build(),
    RequestBody.fromBytes(imageBytes)
);

// Generate presigned URL (for direct uploads)
S3Presigner presigner = S3Presigner.builder()
    .endpointOverride(URI.create("https://" + accountId + ".r2.cloudflarestorage.com"))
    .region(Region.of("auto"))
    .credentialsProvider(StaticCredentialsProvider.create(credentials))
    .build();

PresignedPutObjectRequest presignedRequest = presigner.presignPutObject(
    PutObjectPresignRequest.builder()
        .signatureDuration(Duration.ofMinutes(15))
        .putObjectRequest(PutObjectRequest.builder()
            .bucket("shopbuilder-assets")
            .key("uploads/" + filename)
            .build())
        .build()
);
```

## Pages Direct Upload

### Overview

Pages Direct Upload allows deploying static sites via API without GitHub integration. Useful for:
- CI/CD pipelines (Woodpecker, GitHub Actions)
- Custom build processes
- Multi-tenant site deployments

### API Usage

```bash
# 1. Create deployment
curl -X POST \
  "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/pages/projects/${PROJECT_NAME}/deployments" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: multipart/form-data" \
  -F "manifest=@manifest.json" \
  -F "<file_hash>=@dist/index.html" \
  -F "<file_hash>=@dist/assets/main.js"
```

### Manifest Format

```json
{
  "/index.html": {
    "hash": "abc123...",
    "size": 1234
  },
  "/assets/main.js": {
    "hash": "def456...",
    "size": 5678
  }
}
```

### Java Implementation

```java
@Service
public class PagesDeploymentService {

    private final WebClient webClient;
    private final ObjectMapper objectMapper;

    @Value("${cloudflare.account-id}")
    private String accountId;

    // Helper method for SHA-256 hashing
    private String sha256(byte[] data) {
        return DigestUtils.sha256Hex(data); // Apache Commons Codec
    }

    public Mono<DeploymentResponse> deploy(String projectName, Map<String, byte[]> files) {
        MultipartBodyBuilder builder = new MultipartBodyBuilder();

        // Build manifest
        Map<String, FileInfo> manifest = files.entrySet().stream()
            .collect(Collectors.toMap(
                Map.Entry::getKey,
                e -> new FileInfo(sha256(e.getValue()), e.getValue().length)
            ));

        builder.part("manifest", objectMapper.writeValueAsString(manifest));

        // Add files
        files.forEach((path, content) -> {
            String hash = sha256(content);
            builder.part(hash, content);
        });

        return webClient.post()
            .uri("/accounts/{accountId}/pages/projects/{projectName}/deployments",
                 accountId, projectName)
            .body(BodyInserters.fromMultipartData(builder.build()))
            .retrieve()
            .bodyToMono(DeploymentResponse.class);
    }
}
```

## Custom Hostnames

### Overview

Custom Hostnames enable multi-tenant SaaS where each customer can use their own domain. The workflow:

1. Customer adds their domain in your app
2. Your app creates a Custom Hostname via API
3. Customer adds a CNAME to your Cloudflare zone
4. Cloudflare provisions SSL automatically

### API Usage

```bash
# Create custom hostname
curl -X POST \
  "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/custom_hostnames" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "hostname": "shop.customer.com",
    "ssl": {
      "method": "http",
      "type": "dv",
      "settings": {
        "min_tls_version": "1.2"
      }
    }
  }'

# Check status
curl "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/custom_hostnames/${HOSTNAME_ID}" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}"

# Delete custom hostname
curl -X DELETE \
  "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/custom_hostnames/${HOSTNAME_ID}" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}"
```

### Java Implementation

```java
@Service
public class CustomHostnameService {

    private final WebClient cloudflareClient;

    @Value("${cloudflare.zone-id}")
    private String zoneId;

    public Mono<CustomHostname> createHostname(String hostname) {
        return cloudflareClient.post()
            .uri("/zones/{zoneId}/custom_hostnames", zoneId)
            .bodyValue(Map.of(
                "hostname", hostname,
                "ssl", Map.of(
                    "method", "http",
                    "type", "dv",
                    "settings", Map.of("min_tls_version", "1.2")
                )
            ))
            .retrieve()
            .bodyToMono(CloudflareResponse.class)
            .map(r -> r.getResult());
    }

    public Mono<CustomHostname> getHostnameStatus(String hostnameId) {
        return cloudflareClient.get()
            .uri("/zones/{zoneId}/custom_hostnames/{hostnameId}", zoneId, hostnameId)
            .retrieve()
            .bodyToMono(CloudflareResponse.class)
            .map(r -> r.getResult());
    }
}
```

### SSL Validation Methods

| Method | Description | Use Case |
|--------|-------------|----------|
| `http` | HTTP validation via /.well-known/ | Most common, automated |
| `txt` | TXT DNS record validation | When HTTP not possible |
| `email` | Email validation | Rarely used |

### Customer Instructions

Provide customers with these DNS instructions:

```
Add a CNAME record:
  Name: shop (or their subdomain)
  Target: your-zone.pages.dev (or fallback origin)
  Proxy: OFF (DNS only initially, can enable after verification)
```

## Cache Purge

### Overview

Cache Purge invalidates CDN cache for immediate content updates. Use sparingly as it affects performance.

### API Usage

```bash
# Purge specific URLs
curl -X POST \
  "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/purge_cache" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"files": ["https://example.com/image.png", "https://example.com/style.css"]}'

# Purge everything (use carefully!)
curl -X POST \
  "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/purge_cache" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"purge_everything": true}'

# Purge by prefix (path)
curl -X POST \
  "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/purge_cache" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"prefixes": ["https://example.com/products/"]}'

# Purge by cache tag (Enterprise only)
curl -X POST \
  "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/purge_cache" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"tags": ["product-123", "category-456"]}'
```

### Java Implementation

```java
@Service
public class CachePurgeService {

    private final WebClient cloudflareClient;

    @Value("${cloudflare.zone-id}")
    private String zoneId;

    public Mono<PurgeResponse> purgeUrls(List<String> urls) {
        return cloudflareClient.post()
            .uri("/zones/{zoneId}/purge_cache", zoneId)
            .bodyValue(Map.of("files", urls))
            .retrieve()
            .bodyToMono(CloudflareResponse.class);
    }

    public Mono<PurgeResponse> purgePrefix(String prefix) {
        return cloudflareClient.post()
            .uri("/zones/{zoneId}/purge_cache", zoneId)
            .bodyValue(Map.of("prefixes", List.of(prefix)))
            .retrieve()
            .bodyToMono(CloudflareResponse.class);
    }

    public Mono<PurgeResponse> purgeAll() {
        return cloudflareClient.post()
            .uri("/zones/{zoneId}/purge_cache", zoneId)
            .bodyValue(Map.of("purge_everything", true))
            .retrieve()
            .bodyToMono(CloudflareResponse.class);
    }
}
```

### Best Practices

1. **Prefer targeted purges** over `purge_everything`
2. **Use cache tags** for related content (Enterprise)
3. **Debounce purges** to avoid rate limits
4. **Log purge operations** for debugging

## Terraform Module Usage

### Basic Configuration

```hcl
module "cloudflare" {
  source = "../../modules/cloudflare"

  account_id  = var.cloudflare_account_id
  zone_name   = "staticshop.io"
  environment = "prod"

  r2_bucket = {
    name     = "shopbuilder-assets-prod"
    location = "WEUR"
  }

  pages_project = {
    name              = "shopbuilder-frontend"
    production_branch = "main"
    custom_domain     = "app.staticshop.io"
  }
}
```

### Outputs

The module provides API endpoint outputs for application configuration:

```hcl
output "r2_endpoint" {
  value = module.cloudflare.r2_endpoint
}

output "api_endpoints" {
  value = module.cloudflare.api_endpoints
}
```

## Rate Limits

| API | Limit |
|-----|-------|
| R2 Operations | 1000 requests/second per bucket |
| Pages Deployments | 500 deployments/day |
| Custom Hostnames | 100 requests/5 minutes |
| Cache Purge | 1000 files/request, 30 requests/minute |

## Troubleshooting

### Common Issues

**R2 Access Denied**
- Verify R2 API token has correct bucket permissions
- Check endpoint URL format: `https://{account_id}.r2.cloudflarestorage.com`

**Custom Hostname SSL Pending**
- Customer hasn't added CNAME record yet
- DNS propagation in progress (wait up to 24 hours)
- Try `txt` validation method if HTTP fails

**Cache Not Clearing**
- Check zone ID is correct
- Verify API token has Cache Purge permission
- Cache may be held at edge; wait 30 seconds

**Pages Deployment Failed**
- Verify manifest file hashes match content
- Check file count doesn't exceed limits
- Ensure project name exists

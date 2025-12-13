# Observability Stack: Grafana Cloud + Sentry

This document describes how to configure and use the observability stack for ShopBuilder using Grafana Cloud for metrics/traces and Sentry for error tracking.

## Overview

The observability stack consists of two main components:

1. **Grafana Cloud** - Metrics and distributed tracing via OpenTelemetry Protocol (OTLP)
2. **Sentry** - Error tracking and performance monitoring

## Prerequisites

### Grafana Cloud Setup

1. Create a Grafana Cloud account at https://grafana.com/products/cloud/
2. Create a new stack or use an existing one
3. Note your stack's region (e.g., `prod-eu-west-0`) from the URL

### Sentry Setup

1. Create a Sentry account at https://sentry.io/
2. Create a new project for your Spring Boot application
3. Note your organization slug and project slug from the URL

## Configuration

### Step 1: Generate Grafana Cloud Credentials

1. Go to your Grafana Cloud Portal
2. Navigate to **Connections** > **OpenTelemetry**
3. Click **Configure** to view your OTLP settings
4. Note the following:
   - **OTLP Endpoint**: `https://otlp-gateway-{region}.grafana.net/otlp`
   - **Instance ID**: Your numeric instance ID (e.g., `123456`)
5. Generate an API token:
   - Go to **Access Policies** in Grafana Cloud
   - Create a new token with scopes: `metrics:write`, `traces:write`, `logs:write`
   - Save the generated token securely

### Step 2: Generate Sentry Credentials

1. Go to your Sentry project settings
2. Navigate to **Client Keys (DSN)**
3. Copy the DSN URL
4. For source maps and release management:
   - Go to https://sentry.io/settings/account/api/auth-tokens/
   - Create a token with scopes: `project:releases`, `org:read`

### Step 3: Add Secrets to SOPS

Add the following to your environment's secrets file (e.g., `secrets/production.yaml`):

```yaml
# Grafana Cloud
GRAFANA_CLOUD_OTLP_ENDPOINT: https://otlp-gateway-prod-eu-west-0.grafana.net/otlp
GRAFANA_CLOUD_INSTANCE_ID: "123456"
GRAFANA_CLOUD_API_TOKEN: glc_your_api_token_here

# Sentry
SENTRY_DSN: https://your_key@o123456.ingest.sentry.io/1234567
SENTRY_AUTH_TOKEN: sntrys_your_auth_token_here
SENTRY_ORG: your-organization
SENTRY_PROJECT: shopbuilder
```

Then encrypt the file:

```bash
export SOPS_AGE_KEY_FILE=keys/production.age.key
sops -e secrets/production.yaml > secrets/production.enc.yaml.tmp && \
  mv secrets/production.enc.yaml.tmp secrets/production.enc.yaml
rm secrets/production.yaml
```

### Step 4: Configure Environment Variables

Add the following to your `.env` file (copy from `.env.example`):

```bash
# Grafana Cloud OTLP endpoint
GRAFANA_CLOUD_OTLP_ENDPOINT=https://otlp-gateway-prod-eu-west-0.grafana.net/otlp

# Generate OTLP headers with: echo -n "<instance_id>:<api_token>" | base64
# Example: echo -n "123456:glc_abc123" | base64
OTEL_EXPORTER_OTLP_HEADERS=Authorization=Basic MTIzNDU2OmdsY19hYmMxMjM=

# Service identification
OTEL_SERVICE_NAME=shopbuilder-api
OTEL_SERVICE_NAME_WORKERS=shopbuilder-workers
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production

# Sentry configuration
SENTRY_DSN=https://your_key@o123456.ingest.sentry.io/1234567
SENTRY_ENVIRONMENT=production
SENTRY_TRACES_SAMPLE_RATE=0.1
```

## Disabling Observability

If you don't want to use Grafana Cloud for metrics/traces, you must explicitly disable the OTLP exporters to avoid connection errors in the application logs.

In your `.env` file, set:

```bash
# Disable OTLP export when not using Grafana Cloud
OTEL_METRICS_EXPORTER=none
OTEL_TRACES_EXPORTER=none
GRAFANA_CLOUD_OTLP_ENDPOINT=
OTEL_EXPORTER_OTLP_HEADERS=
```

Similarly, to disable Sentry error tracking:

```bash
SENTRY_DSN=
```

When disabled, the Spring applications will start without observability features and no export errors will be logged.

## Spring Boot Application Configuration

The Spring Boot application should be configured to use the OpenTelemetry environment variables. Add these dependencies to your `build.gradle`:

```gradle
// OpenTelemetry
implementation 'io.opentelemetry.instrumentation:opentelemetry-spring-boot-starter'

// Sentry
implementation 'io.sentry:sentry-spring-boot-starter-jakarta'
```

### application.yml Configuration

```yaml
# OpenTelemetry configuration (uses OTEL_* environment variables automatically)
management:
  otlp:
    metrics:
      export:
        enabled: ${OTEL_METRICS_EXPORTER:otlp}
    tracing:
      endpoint: ${OTEL_EXPORTER_OTLP_ENDPOINT:}

# Sentry configuration
sentry:
  dsn: ${SENTRY_DSN:}
  environment: ${SENTRY_ENVIRONMENT:production}
  traces-sample-rate: ${SENTRY_TRACES_SAMPLE_RATE:0.1}
  # Enable automatic Spring MVC exception capturing
  exception-resolver-order: -2147483647
```

## Key Metrics to Monitor

### RED Metrics (Request, Error, Duration)
- `http.server.requests` - Request count and latency
- `http.server.requests{status=5xx}` - Server error rate
- `http.server.requests{status=4xx}` - Client error rate

### JVM Metrics
- `jvm.memory.used` - Heap and non-heap memory usage
- `jvm.gc.pause` - Garbage collection pause times
- `jvm.threads.live` - Active thread count

### Database Metrics
- `hikaricp.connections.active` - Active database connections
- `hikaricp.connections.pending` - Pending connection requests

### RabbitMQ Metrics
- `rabbitmq.consumed` - Messages consumed
- `rabbitmq.published` - Messages published

### Custom Business Metrics
Add custom metrics in your application code:

```java
@Component
public class OrderMetrics {
    private final MeterRegistry registry;
    private final Counter ordersCreated;

    public OrderMetrics(MeterRegistry registry) {
        this.registry = registry;
        this.ordersCreated = Counter.builder("orders.created")
            .description("Number of orders created")
            .register(registry);
    }

    public void recordOrderCreated() {
        ordersCreated.increment();
    }
}
```

## Grafana Dashboards

### Recommended Dashboards

1. **Spring Boot Overview** - Import dashboard ID: `12464`
2. **JVM (Micrometer)** - Import dashboard ID: `4701`
3. **HTTP Endpoints** - Import dashboard ID: `17175`

### Creating Custom Dashboards

1. Go to your Grafana Cloud instance
2. Navigate to **Dashboards** > **New Dashboard**
3. Add panels for:
   - Request rate: `sum(rate(http_server_requests_seconds_count[5m]))`
   - P99 latency: `histogram_quantile(0.99, sum(rate(http_server_requests_seconds_bucket[5m])) by (le))`
   - Error rate: `sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m])) / sum(rate(http_server_requests_seconds_count[5m]))`

## Alerting Rules

### Setting Up Alerts in Grafana Cloud

1. Navigate to **Alerting** > **Alert rules**
2. Create rules for:

#### High Error Rate
```
sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m]))
/
sum(rate(http_server_requests_seconds_count[5m])) > 0.01
```
Threshold: > 1% for 5 minutes

#### High Latency
```
histogram_quantile(0.99, sum(rate(http_server_requests_seconds_bucket[5m])) by (le)) > 2
```
Threshold: P99 > 2 seconds for 5 minutes

#### Low JVM Memory
```
jvm_memory_used_bytes{area="heap"} / jvm_memory_max_bytes{area="heap"} > 0.9
```
Threshold: > 90% for 10 minutes

### Setting Up Alerts in Sentry

1. Go to **Alerts** in your Sentry project
2. Create issue alerts for:
   - New errors (first seen)
   - Regression (previously resolved errors)
   - High volume (error spike)

## Troubleshooting

### No Metrics in Grafana

1. Verify the OTLP endpoint URL is correct
2. Check the Authorization header is properly base64 encoded:
   ```bash
   echo -n "INSTANCE_ID:API_TOKEN" | base64
   ```
3. Verify the application can reach the endpoint:
   ```bash
   curl -v https://otlp-gateway-prod-eu-west-0.grafana.net/otlp/v1/metrics
   ```

### No Errors in Sentry

1. Verify the DSN is correct
2. Check that Sentry SDK is initialized:
   ```java
   // Should log initialization on startup
   @Slf4j
   @SpringBootApplication
   public class Application {
       public static void main(String[] args) {
           SpringApplication.run(Application.class, args);
           log.info("Sentry DSN configured: {}", System.getenv("SENTRY_DSN") != null);
       }
   }
   ```
3. Test error capture manually:
   ```java
   Sentry.captureMessage("Test message from ShopBuilder");
   ```

### High OTLP Export Costs

1. Reduce metrics collection interval (default 60s is recommended)
2. Filter out high-cardinality metrics
3. Reduce traces sample rate: `SENTRY_TRACES_SAMPLE_RATE=0.05`

## Testing the Setup

### Test Metrics Export

```bash
# Check if metrics endpoint is responding
curl http://localhost:8080/actuator/prometheus

# Verify OTLP exporter is working (check application logs)
docker logs shopbuilder-api 2>&1 | grep -i otlp
```

### Test Trace Export

1. Make a request to your API
2. Go to Grafana Cloud > Explore > Select "Traces" data source
3. Search for traces with service name `shopbuilder-api`

### Test Error Reporting

1. Trigger an error in your application (e.g., 500 response)
2. Go to Sentry > Issues
3. Verify the error appears with stack trace

## Security Considerations

1. **Never commit secrets** - Use SOPS encryption for all credentials
2. **Rotate tokens regularly** - API tokens should be rotated every 90 days
3. **Use least privilege** - Only grant necessary scopes to API tokens
4. **Monitor access** - Review access logs in Grafana Cloud and Sentry

## Cost Optimization

### Grafana Cloud
- Use sampling for traces (not all requests need to be traced)
- Set appropriate retention periods
- Filter out health check endpoints from tracing

### Sentry
- Set reasonable traces sample rate (0.1 = 10%)
- Configure release health sampling
- Use issue grouping to reduce noise

## References

- [Grafana Cloud OTLP Documentation](https://grafana.com/docs/grafana-cloud/send-data/otlp/)
- [OpenTelemetry Spring Boot](https://opentelemetry.io/docs/languages/java/getting-started/)
- [Sentry Spring Boot Integration](https://docs.sentry.io/platforms/java/guides/spring-boot/)
- [Spring Boot Actuator Metrics](https://docs.spring.io/spring-boot/docs/current/reference/html/actuator.html#actuator.metrics)

# Email Configuration Guide

This guide covers email configuration for ShopBuilder using [Resend](https://resend.com) as the transactional email service.

## Overview

ShopBuilder uses Resend for sending transactional emails such as:
- Order confirmations
- Shipping notifications
- Password reset emails
- Account verification
- Marketing notifications (with user consent)

## Setup Steps

### 1. Create Resend Account

1. Sign up at [resend.com](https://resend.com)
2. Verify your email address
3. Access the dashboard

### 2. Generate API Key

1. Navigate to **API Keys** in the Resend dashboard
2. Click **Create API Key**
3. Name it (e.g., `shopbuilder-production`)
4. Select permissions:
   - **Full Access** for production API keys
   - **Sending Access** for limited keys
5. Copy the API key (starts with `re_`)

### 3. Add API Key to SOPS

Add the API key to your encrypted secrets:

```bash
# Edit the secrets file
sops secrets/production.enc.yaml

# Add these values:
RESEND_API_KEY: re_your_api_key_here
RESEND_WEBHOOK_SECRET: whsec_your_webhook_secret_here  # Optional, for webhooks
```

### 4. Configure Domain Verification

Domain verification is required to send emails from your domain. Resend requires three DNS records:

#### Get DNS Records from Resend

1. In the Resend dashboard, go to **Domains**
2. Click **Add Domain**
3. Enter your domain (e.g., `staticshop.io`)
4. Resend will provide the required DNS records

#### Add DNS Records via Terraform

Use the DNS module's `email_records` variable:

```hcl
module "dns" {
  source = "../../modules/dns"

  zone_name   = "staticshop.io"
  environment = "prod"

  email_records = {
    enabled = true

    # SPF - Sender Policy Framework
    # Authorizes Resend to send email on behalf of your domain
    spf = {
      value = "v=spf1 include:_spf.resend.com ~all"
    }

    # DKIM - DomainKeys Identified Mail
    # Values provided by Resend during domain setup
    dkim = [
      {
        selector = "resend._domainkey"
        value    = "p=MIGfMA0GCSqGSIb3DQEBA..."  # From Resend
      },
      {
        selector = "resend2._domainkey"
        value    = "p=MIGfMA0GCSqGSIb3DQEBA..."  # From Resend (if provided)
      }
    ]

    # DMARC - Domain-based Message Authentication
    # Policy for handling authentication failures
    dmarc = {
      policy = "quarantine"  # Start with "none" and progress to "quarantine" or "reject"
      rua    = "mailto:dmarc-reports@staticshop.io"
      pct    = 100
    }
  }
}
```

#### DNS Record Types Explained

| Record | Purpose | Example Value |
|--------|---------|---------------|
| **SPF** | Specifies which mail servers can send email for your domain | `v=spf1 include:_spf.resend.com ~all` |
| **DKIM** | Cryptographic signature to verify email authenticity | Public key provided by Resend |
| **DMARC** | Policy for handling emails that fail SPF/DKIM checks | `v=DMARC1; p=quarantine; rua=mailto:...` |

#### DMARC Policy Progression

Start with a monitoring policy and gradually increase strictness:

1. **none** - Monitor only, don't affect delivery
2. **quarantine** - Send failing emails to spam
3. **reject** - Reject failing emails entirely

### 5. Verify Domain in Resend

After adding DNS records:

1. Wait for DNS propagation (can take up to 48 hours, usually faster)
2. In Resend dashboard, click **Verify** next to your domain
3. Once verified, you can send from addresses on that domain

### 6. Configure Webhooks (Optional)

Resend can send webhooks for email events (delivered, bounced, etc.):

1. In Resend dashboard, go to **Webhooks**
2. Add your endpoint URL (e.g., `https://api.staticshop.io/webhooks/resend`)
3. Select events to subscribe to:
   - `email.delivered`
   - `email.bounced`
   - `email.complained`
   - `email.opened` (requires tracking)
   - `email.clicked` (requires tracking)
4. Copy the signing secret and add to SOPS as `RESEND_WEBHOOK_SECRET`

## Multi-Tenant Email Strategy

ShopBuilder supports multiple shops, each potentially needing their own sending domain.

### Option 1: Subdomain per Tenant (Recommended)

Each shop gets a subdomain under the main domain:

```
shop1.notifications.staticshop.io
shop2.notifications.staticshop.io
```

**Advantages:**
- Centralized DNS management
- Easy to provision via Terraform
- Consistent deliverability reputation

**Implementation:**

```hcl
# Create DNS records for tenant subdomains
module "dns" {
  source = "../../modules/dns"

  zone_name   = "staticshop.io"
  environment = "prod"

  email_records = {
    enabled        = true
    sending_domain = "notifications"  # Creates notifications.staticshop.io

    spf = {
      value = "v=spf1 include:_spf.resend.com ~all"
    }

    dkim = [
      {
        selector = "resend._domainkey"  # Selector is relative to sending_domain
        value    = "p=..."
      }
    ]

    dmarc = {
      policy = "quarantine"
      rua    = "mailto:dmarc@staticshop.io"
    }
  }
}
```

Emails would be sent from: `orders@shop1.notifications.staticshop.io`

### Option 2: Custom Domain Delegation

Customers provide their own domain and DNS records:

```
notifications.customershop.com
```

**Advantages:**
- Full brand customization
- Customer owns reputation

**Implementation:**

1. Customer adds domain in Resend (via ShopBuilder UI)
2. Resend provides required DNS records
3. Customer adds records to their DNS
4. Domain is verified and ready to use

**Required customer DNS records:**
- SPF TXT record on root/subdomain
- DKIM TXT record(s) with Resend selectors
- DMARC TXT record at `_dmarc` subdomain

### Hybrid Approach

Combine both options:
- Default: Use subdomain (`shop.notifications.staticshop.io`)
- Premium: Allow custom domain delegation

## Spring Boot Integration

### Configuration

Add to `application.yml`:

```yaml
resend:
  api-key: ${RESEND_API_KEY}
  from-email: ${RESEND_FROM_EMAIL:noreply@staticshop.io}
  webhook-secret: ${RESEND_WEBHOOK_SECRET:}
```

### Service Example

```java
@Service
public class EmailService {

    private final RestClient resendClient;
    private final String fromEmail;

    public EmailService(
            @Value("${resend.api-key}") String apiKey,
            @Value("${resend.from-email}") String fromEmail) {
        this.fromEmail = fromEmail;
        this.resendClient = RestClient.builder()
            .baseUrl("https://api.resend.com")
            .defaultHeader("Authorization", "Bearer " + apiKey)
            .defaultHeader("Content-Type", "application/json")
            .build();
    }

    public void sendOrderConfirmation(Order order) {
        var request = Map.of(
            "from", fromEmail,
            "to", order.getCustomerEmail(),
            "subject", "Order Confirmation #" + order.getId(),
            "html", renderTemplate("order-confirmation", order)
        );

        resendClient.post()
            .uri("/emails")
            .body(request)
            .retrieve()
            .toBodilessEntity();
    }

    // TODO: Implement using a templating engine (Thymeleaf, Freemarker, or Mustache)
    private String renderTemplate(String templateName, Object context) {
        // Example with Thymeleaf:
        // return templateEngine.process(templateName, new Context(Locale.getDefault(), Map.of("order", context)));
        throw new UnsupportedOperationException("Implement template rendering");
    }
}
```

### Webhook Handler

```java
@RestController
@RequestMapping("/webhooks/resend")
public class ResendWebhookController {

    @Value("${resend.webhook-secret}")
    private String webhookSecret;

    @PostMapping
    public ResponseEntity<Void> handleWebhook(
            @RequestBody String payload,
            @RequestHeader("svix-id") String svixId,
            @RequestHeader("svix-timestamp") String svixTimestamp,
            @RequestHeader("svix-signature") String svixSignature) {

        // Verify webhook signature using Svix SDK
        // See: https://resend.com/docs/dashboard/webhooks/introduction
        // and: https://docs.svix.com/receiving/verifying-payloads/how
        if (!verifySignature(payload, svixId, svixTimestamp, svixSignature, webhookSecret)) {
            return ResponseEntity.status(401).build();
        }

        // Process webhook event (implement parseEvent using JSON deserialization)
        var event = parseEvent(payload);
        switch (event.type()) {
            case "email.bounced" -> handleBounce(event);
            case "email.complained" -> handleComplaint(event);
            // ... handle other events
        }

        return ResponseEntity.ok().build();
    }

    // TODO: Implement using Svix Java SDK (com.svix:svix)
    // Example: new Webhook(webhookSecret).verify(payload, headers)
    private boolean verifySignature(String payload, String svixId,
            String svixTimestamp, String svixSignature, String secret) {
        // Implementation required - see Svix SDK documentation
        throw new UnsupportedOperationException("Implement webhook verification");
    }

    private WebhookEvent parseEvent(String payload) {
        // Deserialize JSON payload to WebhookEvent record/class
        throw new UnsupportedOperationException("Implement event parsing");
    }
}
```

## Email Templates

Store email templates in the application or a template service:

### Recommended Template Types

| Template | Purpose | Variables |
|----------|---------|-----------|
| `order-confirmation` | Order placed | order, items, total |
| `order-shipped` | Shipment notification | order, tracking |
| `password-reset` | Password reset link | user, resetLink |
| `welcome` | New account welcome | user, shopName |
| `abandoned-cart` | Cart reminder | cart, items |

### Template Best Practices

1. **Responsive design** - Test on mobile and desktop
2. **Plain text fallback** - Always include plain text version
3. **Unsubscribe link** - Required for marketing emails
4. **Preview text** - First 90 characters appear in inbox preview
5. **Brand consistency** - Match shop branding

## Monitoring and Troubleshooting

### Check Domain Status

```bash
# Via Terraform output
terraform output email_records_summary

# Via dig (check DNS propagation)
dig TXT staticshop.io +short  # SPF
dig TXT resend._domainkey.staticshop.io +short  # DKIM
dig TXT _dmarc.staticshop.io +short  # DMARC
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Domain not verified | DNS not propagated | Wait and retry, check records |
| Emails going to spam | Missing/incorrect SPF/DKIM | Verify DNS records |
| Bounced emails | Invalid recipient | Update email validation |
| Rate limited | Too many requests | Implement rate limiting |

### Resend Dashboard

Monitor email delivery:
- **Logs** - View sent emails and their status
- **Analytics** - Delivery rates, opens, clicks
- **Bounces** - Track and handle bounces

## Security Considerations

1. **API Key Security**
   - Store in SOPS, never in code
   - Use environment variables
   - Rotate periodically

2. **Webhook Verification**
   - Always verify webhook signatures
   - Use HTTPS endpoints only

3. **Rate Limiting**
   - Implement application-level rate limiting
   - Resend has built-in limits per plan

4. **Content Security**
   - Sanitize user input in templates
   - Avoid including sensitive data in emails

## Cost Considerations

Resend pricing is based on emails sent per month:
- Free tier: 3,000 emails/month
- Pro: $20/month for 50,000 emails
- Enterprise: Custom pricing

Plan for growth and monitor usage in the Resend dashboard.

## References

- [Resend Documentation](https://resend.com/docs)
- [Resend API Reference](https://resend.com/docs/api-reference/introduction)
- [SPF Record Syntax](https://www.cloudflare.com/learning/dns/dns-records/dns-spf-record/)
- [DKIM Overview](https://www.cloudflare.com/learning/dns/dns-records/dns-dkim-record/)
- [DMARC Explained](https://www.cloudflare.com/learning/dns/dns-records/dns-dmarc-record/)

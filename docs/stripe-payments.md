# Stripe Payments Configuration

This document describes the Stripe payment integration for ShopBuilder e-commerce transactions.

## Overview

ShopBuilder uses Stripe for payment processing with the following flow:

1. Frontend creates a Checkout Session via the backend API
2. Customer completes payment on the Stripe-hosted checkout page
3. Stripe sends webhook events to the backend
4. Backend validates webhooks and updates order status

## Environment Configuration

### API Keys

Stripe provides separate API keys for test and live environments:

| Environment | Secret Key Prefix | Publishable Key Prefix |
|-------------|-------------------|------------------------|
| Development | `sk_test_...`     | `pk_test_...`          |
| Staging     | `sk_test_...`     | `pk_test_...`          |
| Production  | `sk_live_...`     | `pk_live_...`          |

Keys are obtained from the [Stripe Dashboard](https://dashboard.stripe.com/apikeys).

### Required Secrets

Store these secrets using SOPS encryption (see `docs/secrets-management.md`):

| Secret | Description | Format |
|--------|-------------|--------|
| `STRIPE_SECRET_KEY` | Backend API authentication | `sk_test_...` or `sk_live_...` |
| `STRIPE_WEBHOOK_SECRET` | Webhook signature verification | `whsec_...` |
| `STRIPE_PUBLISHABLE_KEY` | Client-side Stripe.js (safe to expose) | `pk_test_...` or `pk_live_...` |

## Webhook Configuration

### Endpoint URL

Configure webhooks in the Stripe Dashboard for each environment:

| Environment | Webhook Endpoint |
|-------------|------------------|
| Development | `https://api.dev.staticshop.io/webhooks/stripe` |
| Staging     | `https://api.staging.staticshop.io/webhooks/stripe` |
| Production  | `https://api.staticshop.io/webhooks/stripe` |

### Events to Listen For

Configure the following webhook events:

| Event | Description |
|-------|-------------|
| `payment_intent.succeeded` | Payment completed successfully |
| `payment_intent.payment_failed` | Payment attempt failed |
| `checkout.session.completed` | Customer completed checkout |
| `customer.subscription.updated` | Subscription changed (future use) |
| `customer.subscription.deleted` | Subscription cancelled (future use) |

### Webhook Setup Steps

1. Go to [Stripe Dashboard > Webhooks](https://dashboard.stripe.com/webhooks)
2. Click "Add endpoint"
3. Enter the endpoint URL for your environment
4. Select the events listed above
5. Click "Add endpoint"
6. Copy the signing secret (`whsec_...`) and add to SOPS secrets

## Payment Flow

```
┌─────────┐      ┌─────────┐      ┌─────────┐      ┌─────────┐
│ Browser │      │ Backend │      │ Stripe  │      │   DB    │
└────┬────┘      └────┬────┘      └────┬────┘      └────┬────┘
     │                │                │                │
     │ Create Session │                │                │
     │───────────────>│                │                │
     │                │ Create Checkout│                │
     │                │ Session        │                │
     │                │───────────────>│                │
     │                │                │                │
     │                │ Session URL    │                │
     │                │<───────────────│                │
     │ Redirect URL   │                │                │
     │<───────────────│                │                │
     │                │                │                │
     │ Redirect to Stripe Checkout     │                │
     │────────────────────────────────>│                │
     │                │                │                │
     │ Complete payment                │                │
     │ (customer enters card)          │                │
     │                │                │                │
     │ Redirect to success page        │                │
     │<────────────────────────────────│                │
     │                │                │                │
     │                │ Webhook POST   │                │
     │                │<───────────────│                │
     │                │                │                │
     │                │ Verify signature                │
     │                │ Update order   │                │
     │                │───────────────────────────────>│
     │                │                │                │
     │                │ 200 OK         │                │
     │                │───────────────>│                │
     │                │                │                │
```

## Spring Boot Integration

### Webhook Controller Example

```java
@RestController
@RequestMapping("/webhooks")
public class StripeWebhookController {

    @Value("${stripe.webhook.secret}")
    private String webhookSecret;

    @PostMapping("/stripe")
    public ResponseEntity<String> handleStripeWebhook(
            @RequestBody String payload,
            @RequestHeader("Stripe-Signature") String sigHeader) {

        Event event;
        try {
            event = Webhook.constructEvent(payload, sigHeader, webhookSecret);
        } catch (SignatureVerificationException e) {
            return ResponseEntity.status(400).body("Invalid signature");
        }

        try {
            switch (event.getType()) {
                case "payment_intent.succeeded":
                    handlePaymentSucceeded(event);
                    break;
                case "payment_intent.payment_failed":
                    handlePaymentFailed(event);
                    break;
                case "checkout.session.completed":
                    handleCheckoutCompleted(event);
                    break;
                default:
                    log.info("Unhandled event type: {}", event.getType());
                    break;
            }
        } catch (Exception e) {
            log.error("Error processing Stripe webhook event: {}", event.getType(), e);
            // Always return 200 to Stripe to prevent retries, but log the error for investigation
        }

        return ResponseEntity.ok("Success");
    }
}
```

### Application Properties

```yaml
stripe:
  api-key: ${STRIPE_SECRET_KEY}
  webhook:
    secret: ${STRIPE_WEBHOOK_SECRET}
```

## Testing

### Test Mode

Use Stripe test mode with `sk_test_...` keys for development and staging. Test mode:

- Accepts test card numbers (e.g., `4242 4242 4242 4242`)
- Does not process real payments
- Has separate webhook endpoints and signing secrets

### Test Cards

| Card Number | Scenario |
|-------------|----------|
| `4242 4242 4242 4242` | Successful payment |
| `4000 0000 0000 9995` | Declined (insufficient funds) |
| `4000 0000 0000 0002` | Declined (generic) |

Use any future expiry date and any 3-digit CVC.

### Webhook Testing

Use the Stripe CLI to forward webhooks to localhost during development:

```bash
# Install Stripe CLI
brew install stripe/stripe-cli/stripe

# Login to Stripe
stripe login

# Forward webhooks to local endpoint
stripe listen --forward-to localhost:8080/webhooks/stripe

# In another terminal, trigger test events
stripe trigger payment_intent.succeeded
```

## Security Considerations

1. **Never log full webhook payloads** - They contain sensitive customer data
2. **Always verify webhook signatures** - Prevents replay attacks
3. **Use HTTPS** - All webhook endpoints must use TLS
4. **Store secrets securely** - Use SOPS encryption, never commit plaintext
5. **Limit retry attempts** - Stripe retries failed webhooks for up to 3 days
6. **Implement idempotency in webhook handlers** - Webhook handlers must be idempotent to avoid duplicate processing. Store processed webhook event IDs (e.g., in a database) and skip events that have already been processed. This prevents duplicate order fulfillment or other side effects if Stripe retries the same event.

## Monitoring

### Key Metrics to Track

- Webhook delivery success rate
- Payment success/failure rates
- Average checkout session duration
- Webhook processing latency

### Stripe Dashboard

Monitor payments and webhooks at:
- [Payments](https://dashboard.stripe.com/payments)
- [Webhooks](https://dashboard.stripe.com/webhooks)
- [Events](https://dashboard.stripe.com/events)

## Future Enhancements

- **Stripe Connect**: Multi-tenant payouts for marketplace functionality
- **Subscriptions**: Recurring payment support
- **Payment Methods**: Apple Pay, Google Pay, SEPA Direct Debit

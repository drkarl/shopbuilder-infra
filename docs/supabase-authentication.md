# Supabase Authentication Configuration

This document describes the Supabase authentication integration for ShopBuilder user management.

## Overview

ShopBuilder uses Supabase for user authentication with the following flow:

1. Frontend authenticates users via Supabase Auth (email/password, OAuth, magic links)
2. Supabase issues a JWT upon successful authentication
3. Frontend sends the JWT in the `Authorization` header to the backend API
4. Backend validates the JWT using Supabase's JWKS endpoint
5. Backend extracts user context from JWT claims for authorization

## Environment Configuration

### Supabase Projects

Create separate Supabase projects for each environment to ensure data isolation:

| Environment | Project Purpose |
|-------------|-----------------|
| Development | Local development and testing |
| Staging     | Pre-production validation |
| Production  | Live user data and authentication |

### Required Secrets

Store these secrets using SOPS encryption (see `docs/secrets-management.md`):

| Secret | Description | Location in Supabase Dashboard |
|--------|-------------|--------------------------------|
| `SUPABASE_URL` | Project API URL | Project Settings > API > Project URL |
| `SUPABASE_ANON_KEY` | Anonymous (public) key | Project Settings > API > Project API keys |
| `SUPABASE_SERVICE_ROLE_KEY` | Admin key (bypasses RLS) | Project Settings > API > Project API keys |
| `SUPABASE_JWT_SECRET` | JWT signing secret | Project Settings > API > JWT Settings |

### Key Security Considerations

| Key | Client-safe | Server-safe | Purpose |
|-----|-------------|-------------|---------|
| Anon Key | Yes | Yes | Client-side auth, respects RLS |
| Service Role Key | **NO** | Yes | Admin operations, bypasses RLS |
| JWT Secret | **NO** | Yes | Server-side JWT validation |

## Authentication Flow

```
┌─────────┐      ┌──────────┐      ┌─────────┐      ┌─────────┐
│ Browser │      │ Supabase │      │ Backend │      │   DB    │
└────┬────┘      └────┬─────┘      └────┬────┘      └────┬────┘
     │                │                 │                │
     │ Sign In        │                 │                │
     │ (email/pass)   │                 │                │
     │───────────────>│                 │                │
     │                │                 │                │
     │ JWT + Session  │                 │                │
     │<───────────────│                 │                │
     │                │                 │                │
     │ API Request    │                 │                │
     │ Authorization: Bearer <JWT>      │                │
     │─────────────────────────────────>│                │
     │                │                 │                │
     │                │ Fetch JWKS      │                │
     │                │ (cached)        │                │
     │                │<────────────────│                │
     │                │                 │                │
     │                │ Validate JWT    │                │
     │                │ Extract Claims  │                │
     │                │                 │                │
     │                │                 │ Query with     │
     │                │                 │ user context   │
     │                │                 │───────────────>│
     │                │                 │                │
     │                │                 │ Result         │
     │                │                 │<───────────────│
     │                │                 │                │
     │ API Response   │                 │                │
     │<─────────────────────────────────│                │
     │                │                 │                │
```

## Spring Boot Integration

### Dependencies

Add the following to `pom.xml`:

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-oauth2-resource-server</artifactId>
</dependency>
```

### Application Configuration

Configure Spring Security to validate Supabase JWTs:

```yaml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          # JWKS endpoint for public key retrieval
          jwk-set-uri: ${SUPABASE_URL}/auth/v1/keys
          # JWT issuer for validation
          issuer-uri: ${SUPABASE_URL}/auth/v1
```

### Security Configuration

```java
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            .authorizeHttpRequests(auth -> auth
                // Public endpoints
                .requestMatchers("/api/public/**").permitAll()
                .requestMatchers("/actuator/health").permitAll()
                // Authenticated endpoints
                .anyRequest().authenticated()
            )
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(jwt -> jwt
                    .jwtAuthenticationConverter(jwtAuthenticationConverter())
                )
            );

        return http.build();
    }

    @Bean
    public JwtAuthenticationConverter jwtAuthenticationConverter() {
        JwtAuthenticationConverter converter = new JwtAuthenticationConverter();
        // Note: JwtGrantedAuthoritiesConverter doesn't support nested claims like
        // "app_metadata.roles" out of the box. Use a custom converter for nested claims.
        converter.setJwtGrantedAuthoritiesConverter(jwt -> {
            Collection<GrantedAuthority> authorities = new ArrayList<>();
            Map<String, Object> appMetadata = jwt.getClaim("app_metadata");
            if (appMetadata != null && appMetadata.containsKey("roles")) {
                @SuppressWarnings("unchecked")
                List<String> roles = (List<String>) appMetadata.get("roles");
                for (String role : roles) {
                    authorities.add(new SimpleGrantedAuthority("ROLE_" + role.toUpperCase()));
                }
            }
            return authorities;
        });
        return converter;
    }
}
```

### Custom JWT Claims Extractor

Extract user information from Supabase JWT claims:

```java
@Component
public class SupabaseUserContext {

    public String getUserId(Jwt jwt) {
        return jwt.getSubject(); // Supabase user UUID
    }

    public String getEmail(Jwt jwt) {
        return jwt.getClaimAsString("email");
    }

    public List<String> getRoles(Jwt jwt) {
        Map<String, Object> appMetadata = jwt.getClaim("app_metadata");
        if (appMetadata != null && appMetadata.containsKey("roles")) {
            return (List<String>) appMetadata.get("roles");
        }
        return Collections.emptyList();
    }

    public boolean hasRole(Jwt jwt, String role) {
        return getRoles(jwt).contains(role);
    }
}
```

### Using JWT in Controllers

```java
@RestController
@RequestMapping("/api/orders")
public class OrderController {

    private final SupabaseUserContext userContext;

    @GetMapping
    public List<Order> getMyOrders(@AuthenticationPrincipal Jwt jwt) {
        String userId = userContext.getUserId(jwt);
        return orderService.findByUserId(userId);
    }

    @PreAuthorize("hasRole('ADMIN')")
    @GetMapping("/all")
    public List<Order> getAllOrders() {
        return orderService.findAll();
    }
}
```

## JWT Structure

Supabase JWTs contain the following claims:

| Claim | Description | Example |
|-------|-------------|---------|
| `sub` | User UUID | `d0c4f2e8-1a2b-3c4d-5e6f-7890abcdef12` |
| `email` | User email address | `user@example.com` |
| `aud` | Audience (authenticated) | `authenticated` |
| `role` | Supabase role | `authenticated` |
| `iat` | Issued at timestamp | `1699999999` |
| `exp` | Expiration timestamp | `1700003599` |
| `app_metadata` | Custom application data | `{"roles": ["user", "admin"]}` |
| `user_metadata` | User profile data | `{"name": "John Doe"}` |

## User Roles and Permissions

### Setting Up Roles

User roles are stored in `app_metadata.roles`. Set roles using the Supabase Admin API:

```javascript
// Using supabase-js with service role key (server-side only)
const { data, error } = await supabaseAdmin.auth.admin.updateUserById(
  userId,
  { app_metadata: { roles: ['user', 'admin'] } }
)
```

### Default Role Structure

| Role | Description | Permissions |
|------|-------------|-------------|
| `user` | Standard customer | View own orders, manage own profile |
| `merchant` | Shop owner | Manage products, view shop orders |
| `admin` | Platform admin | Full system access |

## Supabase Project Setup

### 1. Create Project

1. Go to [supabase.com](https://supabase.com) and create a new project
2. Note the project URL and API keys from Project Settings > API
3. Save the JWT secret from Project Settings > API > JWT Settings

### 2. Configure Authentication Providers

In Authentication > Providers, enable desired auth methods:

| Provider | Use Case |
|----------|----------|
| Email    | Standard email/password login |
| Magic Link | Passwordless email login |
| Google   | Social login |
| GitHub   | Developer-focused social login |

### 3. Configure Email Templates

Customize authentication emails in Authentication > Email Templates:

- Confirmation email
- Password reset email
- Magic link email

### 4. Set Site URL and Redirect URLs

In Authentication > URL Configuration:

| Environment | Site URL | Redirect URLs |
|-------------|----------|---------------|
| Development | `http://localhost:3000` | `http://localhost:3000/auth/callback` |
| Staging     | `https://staging.staticshop.io` | `https://staging.staticshop.io/auth/callback` |
| Production  | `https://staticshop.io` | `https://staticshop.io/auth/callback` |

> **Note:** While `http://localhost` works for email/password authentication, some OAuth providers
> (Google, GitHub, etc.) may require HTTPS even in development. Consider using a local HTTPS proxy
> or Supabase's built-in OAuth flow which handles redirects through their HTTPS domain.

## Testing

### Local Development

1. Set environment variables from SOPS secrets:
   ```bash
   export SUPABASE_URL="https://your-project.supabase.co"
   export SUPABASE_ANON_KEY="your-anon-key"
   ```

2. Test authentication in the frontend to obtain a JWT

3. Use the JWT to test backend endpoints:
   ```bash
   curl -H "Authorization: Bearer <JWT>" \
        http://localhost:8080/api/orders
   ```

### JWT Debugging

Decode JWTs at [jwt.io](https://jwt.io) to inspect claims during development.

> **Security Warning:** Only paste development/test JWTs into online decoders like jwt.io.
> Never paste production tokens—they could be logged or cached, and tokens with long expiry
> remain valid until they expire. For production debugging, use local tools like `jq`:
> ```bash
> echo "<JWT>" | cut -d. -f2 | base64 -d 2>/dev/null | jq
> ```

### Testing with Service Role Key

For admin operations during testing (never in production client code):

```bash
curl -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
     -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
     "${SUPABASE_URL}/auth/v1/admin/users"
```

## Security Considerations

1. **Never expose the Service Role Key** - It bypasses Row Level Security
2. **Never expose the JWT Secret** - It allows forging tokens
3. **Use HTTPS everywhere** - All API calls must use TLS
4. **Validate JWT expiration** - Spring Security does this automatically
5. **Implement token refresh** - Frontend should refresh tokens before expiry
6. **Use Row Level Security (RLS)** - Even with JWT validation, use RLS in Supabase
7. **Audit authentication events** - Monitor for suspicious login patterns

## Monitoring

### Key Metrics

- Authentication success/failure rates
- Token refresh patterns
- JWT validation errors
- Unauthorized access attempts

### Supabase Dashboard

Monitor authentication at:
- [Authentication > Users](https://supabase.com/dashboard/project/_/auth/users)
- [Logs > Auth Logs](https://supabase.com/dashboard/project/_/logs/auth-logs)

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| 401 Unauthorized | Invalid or expired JWT | Check token expiration, refresh token |
| JWT signature invalid | Wrong JWKS endpoint | Verify `jwk-set-uri` matches Supabase URL |
| Missing claims | Token not from Supabase | Ensure frontend uses Supabase Auth |
| CORS errors | Missing CORS config | Configure CORS for Supabase domain |

### Debug Logging

Enable JWT debugging in development:

```yaml
logging:
  level:
    org.springframework.security.oauth2: DEBUG
```

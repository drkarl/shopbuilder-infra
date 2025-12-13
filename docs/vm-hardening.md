# VM Hardening Guide

Security hardening procedures for production VPS instances.

## Overview

This guide covers the security hardening measures implemented for VPS instances in this infrastructure. Hardening can be applied automatically via Terraform cloud-init or manually using the provided scripts.

## Hardening Components

### 1. SSH Hardening

The following SSH security measures are applied:

| Setting | Value | Description |
|---------|-------|-------------|
| `PermitRootLogin` | `no` | Disable direct root SSH access |
| `PasswordAuthentication` | `no` | Disable password-based authentication |
| `PubkeyAuthentication` | `yes` | Enable key-based authentication only |
| `MaxAuthTries` | `3` | Limit authentication attempts |
| `X11Forwarding` | `no` | Disable X11 forwarding |
| `AllowTcpForwarding` | `no` | Disable TCP forwarding |
| `AllowUsers` | `<configured user>` | Restrict SSH to specific users |

**Configuration Location:** `/etc/ssh/sshd_config`

### 2. Firewall (UFW/nftables)

Default firewall policies:

- **Incoming:** Deny all by default
- **Outgoing:** Allow all

Allowed incoming traffic:

| Port | Protocol | Source | Description |
|------|----------|--------|-------------|
| SSH (configurable) | TCP | SSH allowed IPs | SSH access |
| 80 | TCP | Cloudflare IPs* | HTTP traffic |
| 443 | TCP | Cloudflare IPs* | HTTPS traffic |

*When `enable_cloudflare_only=true` (default), HTTP/HTTPS traffic is restricted to Cloudflare IP ranges only.

**Cloudflare IP Ranges:** Updated in the VPS module. Check https://www.cloudflare.com/ips/ for current ranges.

### 3. fail2ban

Brute force protection for SSH:

| Setting | Value | Description |
|---------|-------|-------------|
| `maxretry` | `3` (configurable) | Failures before ban |
| `bantime` | `3600` (configurable) | Ban duration in seconds |
| `findtime` | `600` | Time window for counting failures |

Additional aggressive jail:
- Bans for 24 hours after a single failed attempt (for repeat offenders)

**Configuration Location:** `/etc/fail2ban/jail.local`

### 4. Unattended Security Upgrades

Automatic security updates are enabled:

- Daily package list updates
- Automatic security patch installation
- Automatic reboot at 3:00 AM if required
- Unused kernel/dependency cleanup

**Configuration Locations:**
- `/etc/apt/apt.conf.d/50unattended-upgrades`
- `/etc/apt/apt.conf.d/20auto-upgrades`

### 5. Docker Daemon Hardening

When Docker is installed, the following security options are applied:

| Setting | Value | Description |
|---------|-------|-------------|
| `userns-remap` | `default` | Enable user namespace isolation |
| `no-new-privileges` | `true` | Prevent privilege escalation |
| `live-restore` | `true` | Keep containers running during daemon restart |
| `userland-proxy` | `false` | Use iptables for port forwarding |
| Log rotation | 10MB x 3 files | Prevent disk exhaustion |

**Configuration Location:** `/etc/docker/daemon.json`

### 6. Log Rotation

System and application logs are rotated:

- Daily rotation
- 14 days retention for application logs
- 7 days retention for system logs
- Compression enabled

**Configuration Location:** `/etc/logrotate.d/`

## Terraform Configuration

### Enable Hardening

Hardening is enabled by default. Configure in your VPS module:

```hcl
module "vps" {
  source = "../../modules/vps"

  # ... other configuration ...

  # Hardening options (all default to true)
  enable_hardening           = true
  enable_fail2ban            = true
  enable_unattended_upgrades = true
  enable_docker_hardening    = true

  # SSH configuration
  hardening_ssh_port = 22      # Change to non-standard port if desired
  hardening_ssh_user = "deploy" # User allowed to SSH

  # fail2ban configuration
  fail2ban_maxretry = 3
  fail2ban_bantime  = 3600     # 1 hour ban
}
```

### Disable Hardening

To disable all hardening:

```hcl
module "vps" {
  source = "../../modules/vps"

  enable_hardening = false

  # ... other configuration ...
}
```

### Non-Standard SSH Port

Using a non-standard SSH port (e.g., 2222) provides additional security through obscurity:

```hcl
module "vps" {
  source = "../../modules/vps"

  hardening_ssh_port = 2222
  hardening_ssh_user = "deploy"

  # ... other configuration ...
}
```

## Manual Hardening Scripts

For existing instances or manual hardening:

### Apply Hardening

```bash
# Run with defaults
sudo ./scripts/vm-hardening.sh --ssh-user deploy

# Run with custom SSH port
sudo ./scripts/vm-hardening.sh --ssh-port 2222 --ssh-user deploy

# Dry run (preview changes)
sudo ./scripts/vm-hardening.sh --dry-run

# Skip specific components
sudo ./scripts/vm-hardening.sh --skip-fail2ban --skip-docker
```

### Verify Hardening

```bash
# Run verification
./scripts/verify-hardening.sh

# JSON output for automation
./scripts/verify-hardening.sh --json

# Verify with custom SSH settings
./scripts/verify-hardening.sh --ssh-port 2222 --ssh-user deploy
```

## Verification Checklist

After hardening, verify the following:

- [ ] SSH key authentication works
- [ ] Password authentication is disabled
- [ ] Root login is disabled
- [ ] Firewall is active: `sudo ufw status verbose`
- [ ] fail2ban is running: `sudo fail2ban-client status sshd`
- [ ] Unattended upgrades enabled: `systemctl status unattended-upgrades`
- [ ] Docker daemon configured: `cat /etc/docker/daemon.json`
- [ ] Log rotation configured: `cat /etc/logrotate.d/app-logs`

## Troubleshooting

### SSH Connection Issues

If locked out after hardening:

1. Use cloud provider console access
2. Check `/etc/ssh/sshd_config.original` for backup
3. Restore with: `sudo cp /etc/ssh/sshd_config.original /etc/ssh/sshd_config && sudo systemctl restart sshd`

### fail2ban Issues

Check banned IPs:
```bash
sudo fail2ban-client status sshd
```

Unban an IP:
```bash
sudo fail2ban-client set sshd unbanip <IP_ADDRESS>
```

### Docker Issues with userns-remap

If containers fail to start after enabling user namespace remapping:

1. Check container compatibility with user namespaces
2. For specific containers, you may need to disable userns-remap:
   ```bash
   docker run --userns=host <image>
   ```

## Security Considerations

### IP Whitelisting

For maximum security, restrict SSH access to specific IPs:

```hcl
module "vps" {
  source = "../../modules/vps"

  ssh_allowed_ips = [
    "203.0.113.10/32",  # Office IP
    "198.51.100.0/24",  # VPN range
  ]

  # ... other configuration ...
}
```

### Cloudflare-Only HTTP Traffic

When `enable_cloudflare_only=true`, only Cloudflare IP ranges can access ports 80/443. This:
- Hides your server's real IP
- Provides DDoS protection via Cloudflare
- Enables WAF and other Cloudflare security features

### Regular Updates

Even with unattended-upgrades, periodically:
- Review Cloudflare IP ranges for updates
- Check fail2ban logs for attack patterns
- Review system logs for anomalies
- Update Docker Compose version

## Related Documentation

- [Cloudflare Services](cloudflare-services.md)
- [Woodpecker CI](woodpecker-ci.md)
- [Secrets Management](secrets-management.md)

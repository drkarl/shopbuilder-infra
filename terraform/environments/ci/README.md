# CI Environment - GitHub Actions Self-Hosted Runner

This environment manages GitHub Actions self-hosted runners on Hetzner Cloud.

## Prerequisites

1. **Hetzner Cloud API Token**
   - Create at: https://console.hetzner.cloud → Security → API Tokens
   - Export as: `export HCLOUD_TOKEN=your-token-here`

2. **SSH Key**
   - Generate: `ssh-keygen -t ed25519 -f ~/.ssh/hetzner_id_ed25519`
   - Public key needed for `ssh_public_key` variable

## Quick Start

```bash
# Set Hetzner API token
export HCLOUD_TOKEN=your-token-here

# Copy and edit variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your SSH public key

# Initialize and deploy
terraform init
terraform plan
terraform apply
```

## Post-Deployment Setup

### Option 1: Manual Registration (Default)

After `terraform apply`, complete the GitHub runner setup:

```bash
# SSH to the runner (command shown in terraform output)
ssh runner@<ip-address>

# Get a runner token from GitHub:
# https://github.com/<owner>/shop-builder/settings/actions/runners/new

# Run the installer with token and repo URL
./install-runner.sh <TOKEN> https://github.com/drkarl/shop-builder

# The runner will start automatically
```

### Option 2: Automatic Registration

Set these variables in `terraform.tfvars` for fully automated setup:

```hcl
auto_register_runner = true
github_token         = "ghp_xxxxxxxxxxxx"  # PAT with 'repo' scope
github_owner         = "drkarl"
github_repository    = "shop-builder"
```

The runner will be registered automatically on first boot. No manual steps needed.

**Note**: The GitHub PAT needs the `repo` scope. Create one at:
https://github.com/settings/tokens/new?scopes=repo

## Server Specs

| Type | vCPU | RAM | Disk | Price/mo | Use Case |
|------|------|-----|------|----------|----------|
| `cpx32` | 4 (shared) | 8 GB | 160 GB | €10.99 | Default, good for most CI |
| `cpx42` | 8 (shared) | 16 GB | 320 GB | €19.99 | Docker builds, parallel tests |
| `ccx23` | 4 (dedicated) | 16 GB | 160 GB | €24.49 | Consistent build times |

## Security Features

- **UFW Firewall**: Only SSH allowed inbound
- **fail2ban**: Bans IPs after 3 failed SSH attempts
- **SSH Hardening**: Key-only auth, no root login, AllowUsers
- **Unattended Upgrades**: Automatic security patches
- **Non-root runner**: Runs as `runner` user with sudo

## Maintenance

### Weekly Cleanup (automatic)
A systemd timer runs weekly to clean:
- Docker images/volumes older than 7 days
- Old Gradle caches
- Old workspace directories

### Manual Cleanup
```bash
ssh runner@<ip>
./cleanup.sh
```

### Runner Management
```bash
# Check runner status
ssh runner@<ip>
cd actions-runner
sudo ./svc.sh status

# Restart runner
sudo ./svc.sh stop
sudo ./svc.sh start

# View runner logs
journalctl -u actions.runner.*
```

## Destroying

```bash
terraform destroy
```

**Note**: This will delete the server. Runner registration on GitHub will become stale and need manual cleanup.

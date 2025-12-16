# CI Environment - Ephemeral GitHub Actions Runner

Self-hosted GitHub Actions runner on Hetzner Cloud with an **ephemeral (on-demand)** architecture for cost savings.

## TL;DR - Quick Commands

```bash
# Prerequisites (one-time setup)
export HCLOUD_TOKEN="your-hetzner-token"
export TF_VAR_ssh_public_key="$(cat ~/.ssh/hetzner_id_ed25519.pub)"
export TF_VAR_github_token="ghp_your_github_pat"  # PAT with 'repo' scope

cd terraform/environments/ci
terraform init

# --- DAILY WORKFLOW ---

# Start runner (small, with auto-registration)
terraform apply -auto-approve \
  -var="auto_register_runner=true" \
  -var="github_owner=drkarl" \
  -var="github_repository=shop-builder"

# Start BURST runner (8 vCPU, 16GB RAM) for heavy builds
terraform apply -auto-approve \
  -var="server_size=burst" \
  -var="auto_register_runner=true" \
  -var="github_owner=drkarl" \
  -var="github_repository=shop-builder"

# Stop and destroy (STOPS BILLING)
terraform destroy -auto-approve
```

---

## Table of Contents

1. [Cost-Saving Strategy](#cost-saving-strategy-ephemeral-runners)
2. [Prerequisites](#prerequisites)
3. [Initial Setup](#initial-setup)
4. [Daily Usage](#daily-usage)
5. [One-Liner Commands](#one-liner-commands-with-auto-registration)
6. [Runner Registration Options](#runner-registration)
7. [Server Specifications](#server-specifications)
8. [Security](#security)
9. [Troubleshooting](#troubleshooting)

---

## Cost-Saving Strategy: Ephemeral Runners

### The Problem with Always-On Runners
A self-hosted runner running 24/7 costs:
- cpx32: ~€10.99/month
- cpx42: ~€19.99/month

But most projects only run CI for a few hours per week.

### The Solution: Destroy When Idle
Hetzner bills **by the hour** (rounded up to the nearest hour). The key insight:

| Action | Billing |
|--------|---------|
| Server running | Charged per hour |
| Server **powered off** | Still charged (disk reserved) |
| Server **destroyed** | No charge |

**Shutting down is NOT enough** - you must DESTROY the server to stop billing.

### Ephemeral Workflow
```
┌─────────────────────────────────────────────────────────────────┐
│                    YOUR CI WORKFLOW                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. About to push code / run CI?                                │
│     └─> terraform apply         (~2-3 min provisioning)         │
│                                                                  │
│  2. CI jobs run on self-hosted runner                           │
│     └─> Push commits, open PRs, run multiple jobs               │
│                                                                  │
│  3. Done for the day?                                           │
│     └─> terraform destroy       (billing stops immediately)     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Cost Examples

| Usage Pattern | Monthly Cost (small) | Monthly Cost (burst) |
|--------------|---------------------|---------------------|
| 1 hour/day | ~€0.45 | ~€0.84 |
| 4 hours/day | ~€1.80 | ~€3.36 |
| Always-on | ~€10.99 | ~€19.99 |

**Savings: 80-95%** compared to always-on runners.

### Trade-offs
- **Pro**: Massive cost savings
- **Pro**: Fresh environment every time (no state drift)
- **Con**: 2-3 minute startup time before CI can run
- **Con**: No persistent Gradle/Docker cache (can add later with volumes)

---

## Prerequisites

### 1. Hetzner Cloud API Token
```bash
# Create at: https://console.hetzner.cloud → Security → API Tokens
# Grant "Read & Write" permissions
export HCLOUD_TOKEN="your-token-here"
```

### 2. SSH Key
```bash
# Generate if you don't have one
ssh-keygen -t ed25519 -f ~/.ssh/hetzner_id_ed25519

# Export for Terraform
export TF_VAR_ssh_public_key="$(cat ~/.ssh/hetzner_id_ed25519.pub)"
```

### 3. GitHub PAT (for auto-registration)
```bash
# Create at: https://github.com/settings/tokens/new?scopes=repo
# Only needs 'repo' scope
export TF_VAR_github_token="ghp_xxxxxxxxxxxx"
```

---

## Initial Setup

```bash
cd terraform/environments/ci

# Option A: Use environment variables (recommended for ephemeral)
# Set the exports from Prerequisites above, then:
terraform init

# Option B: Use terraform.tfvars file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
```

---

## Daily Usage

### Simple Commands (if using terraform.tfvars)

```bash
# Create runner
terraform apply

# Destroy when done
terraform destroy
```

### Switching Server Sizes

```bash
# Default: small (cpx32 - 4 vCPU, 8GB)
terraform apply

# Burst mode for heavy builds (cpx42 - 8 vCPU, 16GB)
terraform apply -var="server_size=burst"
```

---

## One-Liner Commands with Auto-Registration

For fully automated ephemeral runners, use environment variables + command-line vars.

### Environment Setup (add to ~/.bashrc or ~/.zshrc)

```bash
# Hetzner
export HCLOUD_TOKEN="your-hetzner-api-token"

# SSH (Terraform auto-reads TF_VAR_* variables)
export TF_VAR_ssh_public_key="$(cat ~/.ssh/hetzner_id_ed25519.pub)"

# GitHub PAT for auto-registration
export TF_VAR_github_token="ghp_your_pat_here"

# Optional: set defaults
export TF_VAR_github_owner="drkarl"
export TF_VAR_github_repository="shop-builder"
```

### One-Liner: Start Small Runner with Auto-Registration

```bash
terraform apply -auto-approve \
  -var="auto_register_runner=true" \
  -var="github_owner=drkarl" \
  -var="github_repository=shop-builder"
```

### One-Liner: Start BURST Runner with Auto-Registration

```bash
terraform apply -auto-approve \
  -var="server_size=burst" \
  -var="auto_register_runner=true" \
  -var="github_owner=drkarl" \
  -var="github_repository=shop-builder"
```

### One-Liner: Destroy

```bash
terraform destroy -auto-approve
```

### Shell Aliases (add to ~/.bashrc or ~/.zshrc)

```bash
# Quick runner management
alias ci-up='cd ~/projects/shopbuilder-infra/terraform/environments/ci && terraform apply -auto-approve -var="auto_register_runner=true" -var="github_owner=drkarl" -var="github_repository=shop-builder"'
alias ci-burst='cd ~/projects/shopbuilder-infra/terraform/environments/ci && terraform apply -auto-approve -var="server_size=burst" -var="auto_register_runner=true" -var="github_owner=drkarl" -var="github_repository=shop-builder"'
alias ci-down='cd ~/projects/shopbuilder-infra/terraform/environments/ci && terraform destroy -auto-approve'
alias ci-ssh='ssh runner@$(cd ~/projects/shopbuilder-infra/terraform/environments/ci && terraform output -raw runner_ip)'
```

Then just use:
```bash
ci-up      # Start small runner
ci-burst   # Start burst runner
ci-down    # Destroy (stop billing)
ci-ssh     # SSH into runner
```

### Complete Example Session

```bash
# Morning: Start working on a feature
ci-up
# Wait ~2-3 minutes for provisioning...
# Runner auto-registers with GitHub

# Push code, CI runs on self-hosted runner
git push origin feature-branch

# Need more power for parallel tests?
ci-burst
# Existing server destroyed, new burst server created

# End of day: Stop billing
ci-down

# Cost for 4 hours of burst usage: ~€0.11
```

---

## Runner Registration

### Option A: Manual Registration (Default)

After `terraform apply`:

```bash
# SSH to the runner
ssh runner@$(terraform output -raw runner_ip)

# Get a registration token from GitHub:
# https://github.com/YOUR_OWNER/YOUR_REPO/settings/actions/runners/new

# Run the installer
./install-runner.sh YOUR_TOKEN https://github.com/YOUR_OWNER/YOUR_REPO
```

**Pros**: No PAT needed, simpler security model
**Cons**: Manual step after every `terraform apply`

### Option B: Automatic Registration (Recommended for Ephemeral)

Set via environment variable or terraform.tfvars:

```bash
# Environment variable approach
export TF_VAR_github_token="ghp_xxxxxxxxxxxx"
terraform apply -var="auto_register_runner=true" -var="github_owner=drkarl" -var="github_repository=shop-builder"
```

Or in `terraform.tfvars`:
```hcl
auto_register_runner = true
github_token         = "ghp_xxxxxxxxxxxx"  # PAT with 'repo' scope
github_owner         = "drkarl"
github_repository    = "shop-builder"
```

**Pros**: Fully automated - just `terraform apply` and runner is ready
**Cons**: Requires storing a GitHub PAT

**Security Notes on the PAT**:
- The PAT only needs `repo` scope (not admin)
- It's used only to fetch a short-lived registration token
- Using `TF_VAR_` env vars keeps it out of files entirely
- If using terraform.tfvars, it's gitignored
- Never commit the PAT to version control
- Create at: https://github.com/settings/tokens/new?scopes=repo

**Recommendation**: For ephemeral runners, use auto-registration with environment variables. The convenience of one-liner commands outweighs the minor security trade-off.

---

## Server Specifications

| Size | Type | vCPU | RAM | Disk | Hourly | Monthly (24/7) | Use Case |
|------|------|------|-----|------|--------|----------------|----------|
| `small` | cpx32 | 4 (shared) | 8 GB | 160 GB | €0.015 | €10.99 | Default, sequential jobs |
| `burst` | cpx42 | 8 (shared) | 16 GB | 320 GB | €0.028 | €19.99 | Parallel jobs, Docker builds |
| custom | ccx23 | 4 (dedicated) | 16 GB | 160 GB | €0.034 | €24.49 | Consistent build times |

### Installed Software
- Ubuntu 24.04 LTS
- Docker (latest)
- Java 25 (Temurin/Adoptium)
- Git, jq, curl, htop, tmux, ripgrep, fd-find, bat

---

## Security

### Hardening Applied
- **UFW Firewall**: Only SSH inbound (configurable port)
- **fail2ban**: Auto-bans IPs after 3 failed SSH attempts (1 hour ban)
- **SSH Hardening**: Key-only auth, no root login, AllowUsers whitelist
- **Unattended Upgrades**: Automatic security patches
- **Non-root Runner**: GitHub runner runs as `runner` user

### Security Recommendations

1. **Restrict SSH access** to your IP:
   ```bash
   terraform apply -var='ssh_allowed_ips=["YOUR.IP.ADDRESS/32"]'
   ```

2. **Do NOT use for untrusted PRs**: Self-hosted runners can execute arbitrary code. Only use for:
   - Your own repositories
   - Private repositories with trusted contributors
   - Repositories where you control who can open PRs

3. **Use workflow restrictions**: In your repo settings, restrict which workflows can use self-hosted runners.

4. **Rotate the PAT periodically** if using auto-registration.

5. **Use environment variables** for secrets instead of terraform.tfvars files.

---

## Troubleshooting

### Check Runner Status
```bash
ssh runner@$(terraform output -raw runner_ip)
cd actions-runner
sudo ./svc.sh status
```

### View Runner Logs
```bash
journalctl -u actions.runner.* -f
```

### Check Cloud-Init Progress
```bash
# SSH in and check if provisioning completed
cloud-init status
# Should show "status: done"

# View cloud-init logs
sudo cat /var/log/cloud-init-output.log
```

### Runner Not Showing in GitHub
1. Check cloud-init completed: `cloud-init status`
2. Check runner service: `sudo ./svc.sh status`
3. Re-register manually: `./install-runner.sh TOKEN URL`

### Stale Runner in GitHub UI
After `terraform destroy`, the runner shows as "Offline" in GitHub. Options:
- Wait 14 days for auto-removal
- Manually delete from: `https://github.com/OWNER/REPO/settings/actions/runners`

### SSH Connection Issues
```bash
# Get the SSH command
terraform output -raw ssh_command

# If using custom port, check the output
terraform output ssh_config_entry
```

---

## Configuration Reference

### All Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `server_size` | `"small"` | Size preset: `small`, `burst`, or `custom` |
| `server_type` | `"cpx32"` | Hetzner type (only if server_size=custom) |
| `location` | `"nbg1"` | Datacenter: `nbg1`, `hel1`, `fsn1` |
| `runner_name` | `"github-runner-1"` | Name in Hetzner and GitHub |
| `runner_user` | `"runner"` | Linux user for the runner |
| `runner_labels` | `["self-hosted", "linux", "x64", "hetzner", "builder"]` | GitHub runner labels |
| `ssh_public_key` | (required) | Your SSH public key |
| `ssh_port` | `22` | SSH port |
| `ssh_allowed_ips` | `[]` | CIDR blocks for SSH (empty = all) |
| `auto_register_runner` | `false` | Enable auto-registration |
| `github_token` | `""` | PAT with repo scope |
| `github_owner` | `""` | GitHub user or org |
| `github_repository` | `""` | Repository name |
| `java_version` | `25` | Java version to install |
| `install_docker` | `true` | Install Docker |

### Outputs

| Output | Description |
|--------|-------------|
| `runner_ip` | IPv4 address |
| `ssh_command` | Ready-to-use SSH command |
| `server_type` | Actual Hetzner server type |
| `hourly_cost` | Estimated hourly cost |

---

## Future Enhancements (Not Implemented)

- **Persistent Gradle Cache Volume**: Attach a Hetzner volume for `~/.gradle/caches` to speed up builds
- **Snapshot-based Provisioning**: Create a snapshot after first boot for faster subsequent starts (~30 sec vs ~2-3 min)
- **Auto-scaling**: Multiple runners for parallel workflow jobs
- **Webhook-triggered provisioning**: Auto-create runner when workflow is queued

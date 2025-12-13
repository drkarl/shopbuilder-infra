# Disaster Recovery Runbook

This document provides comprehensive backup and disaster recovery procedures for ShopBuilder infrastructure.

## Table of Contents

1. [Recovery Objectives](#recovery-objectives)
2. [Age Key Backup Procedure](#age-key-backup-procedure)
3. [Database Backup Strategy (Neon)](#database-backup-strategy-neon)
4. [VM Recreation from Terraform](#vm-recreation-from-terraform)
5. [Secret Restoration from SOPS](#secret-restoration-from-sops)
6. [Disaster Severity Levels](#disaster-severity-levels)
7. [Incident Response Checklist](#incident-response-checklist)
8. [DR Drill Schedule](#dr-drill-schedule)

---

## Recovery Objectives

### Recovery Time Objective (RTO)

RTO defines the maximum acceptable time to restore service after an incident.

| Component | RTO Target | Notes |
|-----------|------------|-------|
| VPS/Application | 2 hours | Terraform recreation + deployment |
| Database (Neon) | 30 minutes | PITR restore via Neon Console |
| Secrets (SOPS) | 1 hour | Key recovery + decryption |
| DNS/CDN (Cloudflare) | 15 minutes | Managed service, minimal action required |
| Redis (Upstash) | 30 minutes | Managed service recreation |

### Recovery Point Objective (RPO)

RPO defines the maximum acceptable data loss measured in time.

| Component | RPO Target | Backup Mechanism |
|-----------|------------|------------------|
| Database (Neon) | Near-zero | Continuous WAL archiving (PITR) |
| Application State | Last deployment | Git repository + CI/CD pipeline |
| Secrets | Last commit | SOPS-encrypted files in Git |
| Configuration | Last commit | Terraform state + Git |
| Redis Cache | N/A (cache only) | Ephemeral data, reconstructable |

---

## Age Key Backup Procedure

**CRITICAL**: Age private keys are the master keys to all encrypted secrets. Loss of age keys means permanent loss of access to encrypted secrets.

### Backup Strategy (3-2-1 Rule)

Maintain **3 copies** of each key, on **2 different media types**, with **1 offsite**.

| Copy | Location | Media Type | Access |
|------|----------|------------|--------|
| Primary | Operator workstation | `~/.config/sops/age/keys.txt` or `keys/` directory | Daily use |
| Backup 1 | Password manager | 1Password, Bitwarden, or equivalent | Emergency recovery |
| Backup 2 | Encrypted USB drive | Physical device in secure location (safe) | Cold storage |

### Password Manager Storage Instructions

1. **Create a secure note** in your password manager (1Password, Bitwarden, etc.)
2. **Title**: `ShopBuilder SOPS Age Key - [environment]`
3. **Content**: Paste the entire private key file content
4. **Fields to include**:
   - Environment: `production`, `staging`, or `dev`
   - Public key: For reference (starts with `age1...`)
   - Created date
   - Last rotation date

Example structure:
```
Title: ShopBuilder SOPS Age Key - Production
Type: Secure Note

--- Key Content ---
# created: 2025-01-15T10:30:00Z
# public key: age1abc123...
AGE-SECRET-KEY-1XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

--- Metadata ---
Environment: production
Public Key: age1abc123...
Created: 2025-01-15
Last Verified: 2025-12-13
```

### Encrypted USB Backup

1. **Format USB drive** with encryption (LUKS on Linux, FileVault on macOS, BitLocker on Windows)
2. **Create directory structure**:
   ```
   shopbuilder-keys/
   ├── production.age.key
   ├── staging.age.key
   ├── dev.age.key
   └── README.txt  # Contains public keys and dates
   ```
3. **Store USB** in a fireproof safe or safety deposit box
4. **Update annually** or after any key rotation

### Key Recovery Test Procedure

Perform quarterly to verify backup accessibility.

```bash
# 1. Retrieve key from password manager (copy to a secure temporary file)
KEYFILE=$(mktemp)
cat > "$KEYFILE" << 'EOF'
# paste key content here
EOF

# 2. Set the key file
export SOPS_AGE_KEY_FILE="$KEYFILE"

# 3. Test decryption
sops -d secrets/production.enc.yaml > /dev/null && echo "SUCCESS: Key works" || echo "FAILED: Key invalid"

# 4. Clean up immediately
rm -f "$KEYFILE"
unset SOPS_AGE_KEY_FILE
unset KEYFILE
```

### Key Rotation Procedure

Rotate keys annually or immediately when:
- Team member with key access leaves
- Key compromise is suspected
- Security audit requires it

```bash
# 1. Generate new key
age-keygen -o keys/production.age.key.new

# 2. Get new public key
NEW_PUBLIC_KEY=$(age-keygen -y keys/production.age.key.new)
echo "New public key: $NEW_PUBLIC_KEY"

# 3. Update .sops.yaml: ADD new public key (keep old one temporarily)
# Edit .sops.yaml and add the new age public key alongside the old one

# 4. Re-encrypt atomically using sops updatekeys (no intermediate unencrypted file)
export SOPS_AGE_KEY_FILE=keys/production.age.key
sops updatekeys secrets/production.enc.yaml

# 5. Verify new key can decrypt
export SOPS_AGE_KEY_FILE=keys/production.age.key.new
sops -d secrets/production.enc.yaml > /dev/null && echo "New key verified" || { echo "ERROR: New key failed"; exit 1; }

# 6. Remove old public key from .sops.yaml
# Edit .sops.yaml and remove the old age public key

# 7. Run updatekeys again to remove old key access
export SOPS_AGE_KEY_FILE=keys/production.age.key.new
sops updatekeys secrets/production.enc.yaml

# 8. Replace old key file with new one
mv keys/production.age.key.new keys/production.age.key

# 9. Update all backup locations with new key
# 10. Update CI/CD secrets with new key content
```

---

## Database Backup Strategy (Neon)

Neon PostgreSQL provides automated backup and point-in-time recovery (PITR).

### Backup Mechanism

| Feature | Production | Staging |
|---------|------------|---------|
| Backup Type | Continuous WAL archiving | Continuous WAL archiving |
| PITR Retention | 7 days | 1 day |
| Suspend Timeout | Disabled (always on) | 300 seconds |
| Region | aws-eu-central-1 | aws-eu-central-1 |

**RTO**: 30 minutes | **RPO**: Near-zero (continuous backup)

### No Manual Backup Required

Neon automatically:
- Archives WAL segments continuously
- Maintains point-in-time recovery capability
- Handles storage management

### Restore Procedure

#### Option 1: Neon Console (Recommended)

1. Navigate to [Neon Console](https://console.neon.tech/)
2. Select your project
3. Go to **Branches** tab
4. Click **Create branch**
5. Select **Point in time**
6. Choose your restore timestamp
7. Name the branch (e.g., `restore-2025-12-13-incident`)
8. Click **Create branch**

The new branch contains your database at the specified point in time.

#### Option 2: Terraform (Infrastructure as Code)

```hcl
# Create a restore branch from a point in time
resource "neon_branch" "restore" {
  project_id       = neon_project.this.id
  parent_id        = neon_project.this.default_branch_id
  name             = "restore-2025-12-13"
  parent_timestamp = "2025-12-13T10:30:00Z"  # ISO 8601 format
}

# Create an endpoint for the restored branch
resource "neon_endpoint" "restore" {
  project_id = neon_project.this.id
  branch_id  = neon_branch.restore.id
  type       = "read_write"
}
```

#### Post-Restore Steps

1. **Verify data integrity**
   ```sql
   -- Check row counts on critical tables
   SELECT 'users' as table_name, COUNT(*) FROM users
   UNION ALL
   SELECT 'orders', COUNT(*) FROM orders
   UNION ALL
   SELECT 'products', COUNT(*) FROM products;
   ```

2. **Update application connection string** (if switching to restored branch)
   ```bash
   # Get new connection strings from Neon Console or Terraform output
   terraform output -raw neon_connection_uri_pooler
   ```

3. **Update SOPS secrets** with new connection strings
4. **Redeploy application** with updated secrets

---

## VM Recreation from Terraform

### Prerequisites

Before recreation, ensure you have:

- [ ] Age private key for SOPS decryption
- [ ] Cloud provider credentials (Scaleway/OVH)
- [ ] SSH public key for VPS access
- [ ] Access to this Git repository

### Complete Infrastructure Loss Scenario

**RTO**: 2 hours | **RPO**: Last deployment

#### Step 1: Retrieve Age Key

```bash
# From password manager, create the key file
mkdir -p keys
# Paste key content from password manager
vim keys/production.age.key
chmod 600 keys/production.age.key
```

#### Step 2: Set Up Environment

```bash
# Clone repository (if needed)
git clone https://github.com/drkarl/shopbuilder-infra.git
cd shopbuilder-infra

# Set cloud provider credentials

# Scaleway (REQUIRED - primary VPS provider)
export SCW_ACCESS_KEY="your-access-key"
export SCW_SECRET_KEY="your-secret-key"
export SCW_DEFAULT_PROJECT_ID="your-project-id"

# OVH (OPTIONAL - only if using OVH as secondary provider)
# Uncomment if OVH resources are configured in Terraform
# export OVH_ENDPOINT="ovh-eu"
# export OVH_APPLICATION_KEY="your-app-key"
# export OVH_APPLICATION_SECRET="your-app-secret"
# export OVH_CONSUMER_KEY="your-consumer-key"

# Neon (REQUIRED - database provider)
export NEON_API_KEY="your-neon-api-key"

# Upstash (REQUIRED - Redis cache provider)
export TF_VAR_upstash_email="your-email"
export TF_VAR_upstash_api_key="your-api-key"
```

#### Step 3: Decrypt Secrets

```bash
export SOPS_AGE_KEY_FILE=keys/production.age.key
sops -d secrets/production.enc.yaml > .env.production
```

#### Step 4: Recreate Infrastructure

```bash
cd terraform/environments/prod

# Initialize Terraform
terraform init

# Review the plan
terraform plan -out=recovery.tfplan

# Apply (creates new VPS, DNS records, etc.)
terraform apply recovery.tfplan
```

#### Step 5: Deploy Application

```bash
# Get new VPS IP
VPS_IP=$(terraform output -raw vps_public_ip)

# SSH to verify VPS is ready
ssh root@$VPS_IP "docker --version"

# Deploy application (adjust based on your deployment method)
# Option A: Via CI/CD - trigger a new deployment
# Option B: Manual deployment
scp .env.production root@$VPS_IP:/opt/shopbuilder/.env
scp docker/docker-compose.yml root@$VPS_IP:/opt/shopbuilder/
ssh root@$VPS_IP "cd /opt/shopbuilder && docker compose pull && docker compose up -d"
```

#### Step 6: Update DNS (If IP Changed)

If Terraform manages DNS, records will update automatically. Otherwise:

```bash
# Via Cloudflare API or dashboard
# Update A record to point to new VPS IP
```

#### Step 7: Verify Services

```bash
# Check application health
curl -s https://your-domain.com/health | jq .

# Check database connectivity
ssh root@$VPS_IP "docker compose exec app curl localhost:8080/actuator/health"

# Verify SSL certificate
curl -sI https://your-domain.com | grep -i "HTTP/2 200"
```

#### Step 8: Clean Up Local Secrets

```bash
# Remove decrypted secrets from local filesystem (contains sensitive credentials)
rm -f .env.production

# Verify cleanup
ls -la .env.production 2>/dev/null && echo "WARNING: File still exists" || echo "Cleanup complete"
```

### Partial Recovery Scenarios

#### VPS Only (Database and DNS Intact)

```bash
cd terraform/environments/prod
terraform apply -replace="module.vps.scaleway_instance.this"
# Then redeploy application
```

#### Database Only (VPS Intact)

```bash
# Create restore branch in Neon (see Database section)
# Update connection strings in secrets
# Redeploy application
```

---

## Secret Restoration from SOPS

### Scenario: Secrets Corrupted or Lost

If encrypted secret files are corrupted:

1. **Restore from Git history**
   ```bash
   # Find last known good version
   git log --oneline secrets/production.enc.yaml

   # Restore specific version
   git checkout <commit-hash> -- secrets/production.enc.yaml
   ```

2. **Verify decryption works**
   ```bash
   export SOPS_AGE_KEY_FILE=keys/production.age.key
   sops -d secrets/production.enc.yaml
   ```

### Scenario: Age Key Lost

**CRITICAL**: If all copies of an age private key are lost, the corresponding encrypted secrets cannot be recovered.

**Prevention is critical.** If key is lost:

1. **Recreate secrets manually**
   - Rotate all API keys and passwords at their sources
   - Generate new credentials for all services
   - Create new secrets file from template

2. **Generate new age key and update infrastructure**
   ```bash
   age-keygen -o keys/production.age.key
   # Update .sops.yaml with new public key
   # Encrypt new secrets
   # Update CI/CD with new key
   ```

---

## Disaster Severity Levels

| Level | Description | Examples | RTO Target | Escalation |
|-------|-------------|----------|------------|------------|
| **P0** | Complete Outage | VPS destroyed, all services down | 2 hours | Immediate, all hands |
| **P1** | Database Loss | Data corruption, accidental deletion | 30 minutes | Immediate |
| **P2** | Secret Compromise | Key exposure, credential leak | 1 hour | Immediate |
| **P3** | Service Degradation | Single container down, slow response | 4 hours | Normal business hours |
| **P4** | Minor Issue | Non-critical feature unavailable | 24 hours | Low priority |

### Escalation Contacts

> **Note**: Fill in contact details before the first DR drill. Update this table with your team's actual contact methods (Slack handles, phone numbers, PagerDuty schedules).

| Role | Contact | When to Engage |
|------|---------|----------------|
| On-call Engineer | [Define contact method] | All P0-P2 incidents |
| Infrastructure Lead | [Define contact method] | P0-P1 incidents |
| Security Team | [Define contact method] | P2 (secret compromise) |

---

## Incident Response Checklist

### Immediate Actions (First 15 Minutes)

- [ ] **Assess scope**: Identify affected systems and services
- [ ] **Communicate**: Alert stakeholders via designated channel
- [ ] **Preserve evidence**: If security-related, capture logs before taking action
- [ ] **Assign roles**: Incident Commander, Communications, Technical Lead

### Investigation Phase

- [ ] **Identify root cause**: Review logs, metrics, recent changes
- [ ] **Determine blast radius**: What else could be affected?
- [ ] **Document timeline**: Record all actions with timestamps

### Recovery Phase

- [ ] **Execute recovery procedure**: Follow relevant runbook section
- [ ] **Verify services**: Test all critical functionality
- [ ] **Monitor closely**: Watch for recurrence for 24 hours

### Post-Incident

- [ ] **Conduct retrospective**: Within 48 hours of resolution
- [ ] **Document lessons learned**: Update runbooks as needed
- [ ] **Implement preventive measures**: Address root cause
- [ ] **Communicate resolution**: Notify all stakeholders

### Incident Log Template

```markdown
## Incident: [Brief Description]
**Severity**: P[0-4]
**Status**: [Investigating/Identified/Monitoring/Resolved]
**Started**: YYYY-MM-DD HH:MM UTC
**Resolved**: YYYY-MM-DD HH:MM UTC
**Duration**: X hours Y minutes

### Timeline
- HH:MM - [Event description]
- HH:MM - [Action taken]

### Root Cause
[Description of what caused the incident]

### Resolution
[Description of how it was resolved]

### Action Items
- [ ] [Preventive measure 1]
- [ ] [Preventive measure 2]
```

---

## DR Drill Schedule

### Quarterly DR Drills

Conduct DR drills on the **second Monday of each quarter** to verify recovery procedures.

| Quarter | Month | Drill Type | Description |
|---------|-------|------------|-------------|
| Q1 | January | Age Key Recovery | Retrieve key from password manager, decrypt secrets |
| Q2 | April | Database Restoration | Create PITR branch, verify data integrity |
| Q3 | July | VM Recreation | Destroy and recreate staging VPS from Terraform |
| Q4 | October | Full DR Test | Complete end-to-end disaster recovery simulation |

### Drill Procedures

#### Q1: Age Key Recovery Test

1. Retrieve production age key from password manager
2. Save to temporary location
3. Decrypt production secrets file
4. Verify decryption succeeds
5. Clean up temporary key file
6. Document results

**Success Criteria**: Secrets decrypt successfully within 15 minutes

#### Q2: Database Restoration Test

1. Note current row counts for critical tables
2. Create PITR branch to 1 hour ago in Neon
3. Connect to restored branch
4. Verify data integrity
5. Delete test branch
6. Document results

**Success Criteria**: Database restored and verified within 30 minutes

#### Q3: VM Recreation Test (Staging Only)

1. Document current staging VPS state
2. Destroy staging VPS via Terraform
3. Recreate from Terraform
4. Deploy application
5. Run smoke tests
6. Document results

**Success Criteria**: Staging environment fully operational within 2 hours

#### Q4: Full DR Test

1. Simulate complete infrastructure loss scenario (staging)
2. Execute full recovery procedure:
   - Retrieve keys from backup
   - Recreate infrastructure
   - Restore database to point in time
   - Deploy application
   - Verify all services
3. Document timeline and issues encountered
4. Update runbook with lessons learned

**Success Criteria**: All services restored within RTO targets

### Drill Documentation

After each drill, complete:

```markdown
## DR Drill Report

**Date**: YYYY-MM-DD
**Type**: [Q1/Q2/Q3/Q4] - [Drill Name]
**Participants**: [Names]
**Environment**: [staging/production simulation]

### Results
**Status**: [PASS/FAIL]
**Actual RTO**: [Time taken]
**Target RTO**: [Target time]

### Steps Performed
1. [Step and outcome]
2. [Step and outcome]

### Issues Encountered
- [Issue and resolution]

### Recommendations
- [Improvement suggestion]

### Sign-off
Conducted by: [Name]
Reviewed by: [Name]
```

---

## Related Documentation

- [Secrets Management](./secrets-management.md) - SOPS and age key management
- [Neon Database Configuration](./neon-database.md) - Database setup and PITR
- [Redis Configuration](./redis-configuration.md) - Upstash Redis setup
- [Cloudflare Services](./cloudflare-services.md) - CDN and DNS management
- [Woodpecker CI](./woodpecker-ci.md) - CI/CD pipeline configuration

---

## Revision History

| Date | Version | Author | Changes |
|------|---------|--------|---------|
| 2025-12-13 | 1.0 | Infrastructure Team | Initial version |

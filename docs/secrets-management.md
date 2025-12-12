# Secrets Management with SOPS + age

This document describes how to manage secrets for ShopBuilder infrastructure using [SOPS](https://github.com/getsops/sops) with [age](https://github.com/FiloSottile/age) encryption.

## Quick Start: Pre-commit Hooks

To prevent accidental secret commits, install pre-commit hooks:

```bash
# Install pre-commit (requires Python 3.8+)
pip install pre-commit

# Install the hooks
pre-commit install

# Test the hooks work
pre-commit run --all-files
```

The hooks will automatically run on every commit and block commits containing:
- AWS keys and secrets
- Stripe API keys
- GitHub/GitLab tokens
- Private keys
- High-entropy strings that look like secrets
- And many other secret patterns

### Updating the Secrets Baseline

If detect-secrets flags a false positive, you can add it to the baseline:

```bash
# Audit the current baseline
detect-secrets audit .secrets.baseline

# Update the baseline (only do this for verified false positives)
detect-secrets scan --baseline .secrets.baseline
git add .secrets.baseline
git commit -m "Update secrets baseline"
```

## Overview

- **SOPS** (Secrets OPerationS) - encrypts values in YAML/JSON files while keeping keys readable
- **age** - modern, simple encryption tool used as the encryption backend
- Encrypted secrets are committed to git; only authorized users with the private key can decrypt

## Prerequisites

### Install SOPS

```bash
# macOS
brew install sops

# Linux (download latest release)
curl -LO https://github.com/getsops/sops/releases/download/v3.9.0/sops-v3.9.0.linux.amd64
chmod +x sops-v3.9.0.linux.amd64
sudo mv sops-v3.9.0.linux.amd64 /usr/local/bin/sops

# Verify installation
sops --version
```

### Install age

```bash
# macOS
brew install age

# Linux (download latest release)
curl -LO https://github.com/FiloSottile/age/releases/download/v1.2.0/age-v1.2.0-linux-amd64.tar.gz
tar -xzf age-v1.2.0-linux-amd64.tar.gz
sudo mv age/age /usr/local/bin/
sudo mv age/age-keygen /usr/local/bin/

# Verify installation
age --version
```

## Key Management

### Directory Structure

```
keys/                          # NOT committed to git
├── production.age.key         # Production private key
├── staging.age.key            # Staging private key
└── dev.age.key                # Development private key (optional)
```

### Generate Age Keys

Generate separate key pairs for each environment:

```bash
# Create keys directory (gitignored)
mkdir -p keys

# Generate production key pair
age-keygen -o keys/production.age.key
# Output: Public key: age1abc123...

# Generate staging key pair
age-keygen -o keys/staging.age.key
# Output: Public key: age1def456...

# Extract public key from existing private key
age-keygen -y keys/production.age.key
```

### Update .sops.yaml

After generating keys, update `.sops.yaml` with the actual public keys:

```yaml
creation_rules:
  - path_regex: secrets/production\.enc\.yaml$
    age: age1abc123...  # Replace with actual production public key

  - path_regex: secrets/staging\.enc\.yaml$
    age: age1def456...  # Replace with actual staging public key
```

### Key Storage Best Practices

1. **Never commit private keys** - The `keys/` directory is gitignored
2. **Store private keys securely**:
   - Production: Hardware security module (HSM) or secure vault (e.g., 1Password, AWS Secrets Manager)
   - Staging: Secure team password manager
   - Development: Local machine with full-disk encryption
3. **Backup private keys** - Loss of private key means loss of access to encrypted secrets
4. **Rotate keys periodically** - Re-encrypt secrets with new keys annually or after team changes

## Secret Encryption Workflow

### Creating New Secrets

1. Copy the example template:
   ```bash
   cp secrets/production.enc.yaml.example secrets/production.yaml
   ```

2. Edit with real values:
   ```bash
   # Edit secrets/production.yaml with actual secret values
   ```

3. Encrypt the file (using temp file for safety):
   ```bash
   sops -e secrets/production.yaml > secrets/production.enc.yaml.tmp && \
     mv secrets/production.enc.yaml.tmp secrets/production.enc.yaml
   ```

4. Delete the unencrypted file:
   ```bash
   rm secrets/production.yaml
   ```

5. Commit the encrypted file:
   ```bash
   git add secrets/production.enc.yaml
   git commit -m "Add encrypted production secrets"
   ```

### Decrypting Secrets

Set the `SOPS_AGE_KEY_FILE` environment variable to point to your private key:

```bash
# Decrypt to stdout
export SOPS_AGE_KEY_FILE=keys/production.age.key
sops -d secrets/production.enc.yaml

# Decrypt to file
sops -d secrets/production.enc.yaml > .env.decrypted

# Edit in place (decrypts, opens editor, re-encrypts on save)
sops secrets/production.enc.yaml
```

### Editing Existing Secrets

The easiest way to edit secrets is using SOPS's built-in editor:

```bash
export SOPS_AGE_KEY_FILE=keys/production.age.key
sops secrets/production.enc.yaml
```

This will:
1. Decrypt the file
2. Open it in your `$EDITOR`
3. Re-encrypt when you save and close

### Adding New Keys to Existing Secrets

```bash
export SOPS_AGE_KEY_FILE=keys/production.age.key

# Edit in place
sops secrets/production.enc.yaml
# Add new key-value pairs, save and exit
```

## Environment-Specific Configuration

### Production

- Use dedicated production age key
- Store private key in hardware security module or secure vault
- Limit access to production secrets to senior engineers and automated deployments
- Audit access regularly

### Staging

- Use dedicated staging age key
- Store private key in team password manager
- All team members working on staging can have access

### Development (Optional)

- Use dedicated development age key
- Can be shared among developers
- Contains non-sensitive test values

## CI/CD Integration

### GitHub Actions

Store the age private key as a repository secret:

1. Go to Repository Settings > Secrets and variables > Actions
2. Add secret `SOPS_AGE_KEY` with the private key content

```yaml
# .github/workflows/deploy.yml
jobs:
  deploy:
    steps:
      - name: Decrypt secrets
        env:
          SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
        run: |
          KEY_FILE=$(mktemp)
          trap 'rm -f "$KEY_FILE"' EXIT
          echo "$SOPS_AGE_KEY" > "$KEY_FILE"
          export SOPS_AGE_KEY_FILE="$KEY_FILE"
          sops -d secrets/production.enc.yaml > .env
```

### Woodpecker CI

```yaml
# .woodpecker.yml
steps:
  deploy:
    secrets: [sops_age_key]
    commands:
      - KEY_FILE=$(mktemp)
      - trap 'rm -f "$KEY_FILE"' EXIT
      - echo "$SOPS_AGE_KEY" > "$KEY_FILE"
      - export SOPS_AGE_KEY_FILE="$KEY_FILE"
      - sops -d secrets/production.enc.yaml > .env
```

## Terraform Integration

### Using SOPS Provider

```hcl
# providers.tf
terraform {
  required_providers {
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.0"
    }
  }
}

provider "sops" {}

# secrets.tf
data "sops_file" "secrets" {
  source_file = "${path.module}/../../secrets/production.enc.yaml"
}

# Use decrypted values
resource "example" "resource" {
  api_key = data.sops_file.secrets.data["STRIPE_SECRET_KEY"]
}
```

## Troubleshooting

### "could not decrypt data key"

This means SOPS cannot find the private key to decrypt. Ensure:
1. `SOPS_AGE_KEY_FILE` is set correctly
2. The file exists and contains the private key
3. The public key in `.sops.yaml` matches the private key

### "no matching creation rule found"

The file path doesn't match any regex in `.sops.yaml`. Check:
1. File is in the correct location (`secrets/` directory)
2. File name matches expected pattern (e.g., `production.enc.yaml`)

### "MAC mismatch"

The file was modified after encryption or is corrupted. Re-encrypt from the original source.

## Security Considerations

1. **Private keys are the crown jewels** - Protect them as you would any critical credential
2. **Encrypted files are safe to commit** - Only those with the private key can decrypt
3. **Public keys can be shared** - They're used for encryption only
4. **Audit access** - Track who has access to private keys
5. **Key rotation** - Rotate keys when team members leave or annually

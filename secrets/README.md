# Secrets Directory

This directory contains encrypted secrets managed by SOPS with age encryption.

## Files

| File | Description |
|------|-------------|
| `production.enc.yaml` | Encrypted production secrets |
| `staging.enc.yaml` | Encrypted staging secrets |
| `*.example` | Template files showing expected structure |

## Usage

See [docs/secrets-management.md](../docs/secrets-management.md) for complete documentation on:
- Installing SOPS and age
- Generating age keys
- Encrypting and decrypting secrets
- Key management procedures

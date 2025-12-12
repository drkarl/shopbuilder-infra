# Terraform Infrastructure

This directory contains all Terraform configurations for the ShopBuilder infrastructure.

## Directory Structure

```
terraform/
├── common/                  # Shared configuration (reference only)
│   ├── providers.tf         # Provider definitions
│   ├── variables.tf         # Common variable definitions
│   └── outputs.tf           # Common output definitions
├── modules/                 # Reusable infrastructure modules
│   ├── vps/                 # VPS instance management
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── dns/                 # DNS record management
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── environments/            # Environment-specific configurations
    ├── dev/                 # Development environment
    ├── staging/             # Staging environment
    └── prod/                # Production environment
```

## Providers

This project uses the following cloud providers:

### OVH

OVH is used for domain management and DNS services.

**Required Environment Variables:**
- `OVH_ENDPOINT` - API endpoint (e.g., `ovh-eu`)
- `OVH_APPLICATION_KEY` - Application key
- `OVH_APPLICATION_SECRET` - Application secret
- `OVH_CONSUMER_KEY` - Consumer key

### Scaleway

Scaleway is used for compute resources (VPS instances).

**Required Environment Variables:**
- `SCW_ACCESS_KEY` - Access key
- `SCW_SECRET_KEY` - Secret key
- `SCW_DEFAULT_PROJECT_ID` - Default project ID

## Usage

### Initialize an Environment

```bash
cd terraform/environments/dev
terraform init
```

### Plan Changes

```bash
terraform plan
```

### Apply Changes

```bash
terraform apply
```

### Format Code

```bash
terraform fmt -recursive
```

### Validate Configuration

```bash
terraform validate
```

## Environments

| Environment | Purpose                     | Instance Type |
|-------------|----------------------------|---------------|
| `dev`       | Development and testing     | DEV1-S        |
| `staging`   | Pre-production validation   | DEV1-M        |
| `prod`      | Production workloads        | GP1-S         |

## State Management

Currently using local state backend. Each environment maintains its own state file.

### Migrating to Remote State

To migrate to a remote backend (e.g., Scaleway Object Storage):

1. Uncomment the S3 backend configuration in `backend.tf`
2. Run `terraform init -migrate-state`

## Adding New Modules

1. Create a new directory under `modules/`
2. Add `main.tf`, `variables.tf`, and `outputs.tf`
3. Reference the module from the appropriate environment

## Best Practices

- Always run `terraform plan` before `terraform apply`
- Use variables for all configurable values
- Never commit sensitive values (use environment variables)
- Test changes in `dev` before applying to `staging` or `prod`
- Keep modules small and focused on a single responsibility

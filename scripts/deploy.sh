#!/usr/bin/env bash
#
# ShopBuilder Docker Compose Deployment Script
# Deploys application stack to VPS with SOPS-encrypted secrets
#
# Usage:
#   ./scripts/deploy.sh <environment> [OPTIONS]
#
# Arguments:
#   environment         Target environment: dev, staging, or production
#
# Options:
#   -h, --host          VPS hostname or IP address (or set VPS_HOST)
#   -u, --user          SSH user (default: root, or set VPS_USER)
#   -p, --path          Remote deployment path (default: /opt/shop-builder)
#   -k, --key           Age key file path (default: keys/<environment>.age.key)
#   -t, --tag           Docker image tag to deploy (default: latest)
#   --dry-run           Show what would be done without executing
#   --skip-health       Skip health checks after deployment
#   --help              Show this help message
#
# Environment Variables:
#   VPS_HOST            VPS hostname or IP address
#   VPS_USER            SSH user (default: root)
#   DEPLOY_PATH         Remote deployment path (default: /opt/shop-builder)
#   SOPS_AGE_KEY_FILE   Path to age private key (alternative to -k flag)
#
# Security:
#   - Age private key stays on operator machine (never transferred to VPS)
#   - Secrets decrypted locally, transferred via SCP, cleaned up after deploy
#   - Uses shred for secure deletion of plaintext secrets
#
# Examples:
#   ./scripts/deploy.sh staging
#   ./scripts/deploy.sh production -h 192.168.1.100
#   ./scripts/deploy.sh production --tag v1.2.3
#   VPS_HOST=prod.example.com ./scripts/deploy.sh production

set -euo pipefail

# Script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
ENVIRONMENT=""
VPS_HOST="${VPS_HOST:-}"
VPS_USER="${VPS_USER:-root}"
DEPLOY_PATH="${DEPLOY_PATH:-/opt/shop-builder}"
AGE_KEY_FILE=""
IMAGE_TAG="latest"
DRY_RUN=false
SKIP_HEALTH=false

# Temporary files (will be cleaned up)
TEMP_ENV_FILE=""
DEPLOY_LOG=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

log_debug() {
    if [[ "${DEBUG:-}" == "true" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $1"
    fi
}

show_help() {
    head -40 "$0" | grep "^#" | sed 's/^# \?//'
    exit 0
}

# Cleanup function - runs on exit
cleanup() {
    local exit_code=$?

    # Securely delete temporary env file
    if [[ -n "$TEMP_ENV_FILE" && -f "$TEMP_ENV_FILE" ]]; then
        log_step "Cleaning up local secrets..."
        if command -v shred &> /dev/null; then
            shred -u "$TEMP_ENV_FILE" 2>/dev/null || rm -f "$TEMP_ENV_FILE"
        else
            rm -f "$TEMP_ENV_FILE"
        fi
    fi

    # Close log file if open
    if [[ -n "$DEPLOY_LOG" && -f "$DEPLOY_LOG" ]]; then
        log_info "Deployment log saved to: $DEPLOY_LOG"
    fi

    if [[ $exit_code -ne 0 ]]; then
        log_error "Deployment failed with exit code $exit_code"
    fi

    exit $exit_code
}

trap cleanup EXIT

check_requirements() {
    log_step "Checking requirements..."

    # Check sops is installed
    if ! command -v sops &> /dev/null; then
        log_error "SOPS is not installed."
        log_info "Install with: brew install sops (macOS) or see docs/secrets-management.md"
        exit 1
    fi
    log_debug "SOPS version: $(sops --version 2>/dev/null | head -1)"

    # Check ssh is available
    if ! command -v ssh &> /dev/null; then
        log_error "SSH client is not installed."
        exit 1
    fi

    # Check scp is available
    if ! command -v scp &> /dev/null; then
        log_error "SCP is not installed."
        exit 1
    fi

    # Validate environment
    if [[ "$ENVIRONMENT" != "dev" && "$ENVIRONMENT" != "staging" && "$ENVIRONMENT" != "production" ]]; then
        log_error "Invalid environment: $ENVIRONMENT"
        log_info "Valid environments: dev, staging, production"
        exit 1
    fi

    # Check VPS host is set
    if [[ -z "$VPS_HOST" ]]; then
        log_error "VPS host is required. Use -h flag or set VPS_HOST environment variable."
        exit 1
    fi

    # Set default age key file if not specified
    if [[ -z "$AGE_KEY_FILE" ]]; then
        AGE_KEY_FILE="$PROJECT_ROOT/keys/${ENVIRONMENT}.age.key"
    fi

    # Check SOPS_AGE_KEY_FILE env var as alternative
    if [[ ! -f "$AGE_KEY_FILE" && -n "${SOPS_AGE_KEY_FILE:-}" ]]; then
        AGE_KEY_FILE="$SOPS_AGE_KEY_FILE"
    fi

    # Check age key file exists
    if [[ ! -f "$AGE_KEY_FILE" ]]; then
        log_error "Age key file not found: $AGE_KEY_FILE"
        log_info "Generate with: age-keygen -o $AGE_KEY_FILE"
        log_info "Or set SOPS_AGE_KEY_FILE environment variable"
        exit 1
    fi

    # Check encrypted secrets file exists
    local secrets_file="$PROJECT_ROOT/secrets/${ENVIRONMENT}.enc.yaml"
    if [[ ! -f "$secrets_file" ]]; then
        log_error "Encrypted secrets file not found: $secrets_file"
        log_info "Create from template: cp secrets/${ENVIRONMENT}.enc.yaml.example secrets/${ENVIRONMENT}.enc.yaml"
        exit 1
    fi

    # Check docker-compose.yml exists
    if [[ ! -f "$PROJECT_ROOT/docker/docker-compose.yml" ]]; then
        log_error "docker-compose.yml not found at: $PROJECT_ROOT/docker/docker-compose.yml"
        exit 1
    fi

    # Validate IMAGE_TAG format (alphanumeric, dots, dashes, underscores)
    if [[ ! "$IMAGE_TAG" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        log_error "Invalid IMAGE_TAG format: $IMAGE_TAG"
        log_info "IMAGE_TAG must contain only alphanumeric characters, dots, dashes, and underscores"
        exit 1
    fi

    log_info "All requirements satisfied"
}

decrypt_secrets() {
    log_step "Decrypting secrets locally..."

    local secrets_file="$PROJECT_ROOT/secrets/${ENVIRONMENT}.enc.yaml"

    # Create secure temp file
    TEMP_ENV_FILE=$(mktemp /tmp/.env.XXXXXX)
    chmod 600 "$TEMP_ENV_FILE"

    # Decrypt secrets using SOPS
    export SOPS_AGE_KEY_FILE="$AGE_KEY_FILE"

    if ! sops -d "$secrets_file" > "$TEMP_ENV_FILE" 2>/dev/null; then
        log_error "Failed to decrypt secrets file"
        log_info "Ensure your age key matches the public key used for encryption"
        exit 1
    fi

    # Add image tag override if specified
    if [[ "$IMAGE_TAG" != "latest" ]]; then
        {
            echo ""
            echo "# Deployment overrides"
            echo "FRONTEND_IMAGE=shopbuilder/frontend:${IMAGE_TAG}"
            echo "SPRING_API_IMAGE=shopbuilder/spring-api:${IMAGE_TAG}"
            echo "SPRING_WORKERS_IMAGE=shopbuilder/spring-workers:${IMAGE_TAG}"
        } >> "$TEMP_ENV_FILE"
    fi

    log_info "Secrets decrypted successfully"
}

transfer_files() {
    log_step "Transferring files to VPS..."

    local remote_host="${VPS_USER}@${VPS_HOST}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create directory: $DEPLOY_PATH"
        log_info "[DRY RUN] Would transfer .env file to: $remote_host:$DEPLOY_PATH/.env"
        log_info "[DRY RUN] Would transfer docker-compose.yml to: $remote_host:$DEPLOY_PATH/"
        return
    fi

    # Create deployment directory on VPS if it doesn't exist
    ssh -o ConnectTimeout=10 "$remote_host" "mkdir -p \"$DEPLOY_PATH\"" || {
        log_error "Failed to create deployment directory on VPS"
        exit 1
    }

    # Transfer .env file
    scp -o ConnectTimeout=10 "$TEMP_ENV_FILE" "$remote_host:$DEPLOY_PATH/.env" || {
        log_error "Failed to transfer .env file to VPS"
        exit 1
    }

    # Transfer docker-compose.yml
    scp -o ConnectTimeout=10 "$PROJECT_ROOT/docker/docker-compose.yml" "$remote_host:$DEPLOY_PATH/" || {
        log_error "Failed to transfer docker-compose.yml to VPS"
        exit 1
    }

    log_info "Files transferred successfully"
}

deploy_containers() {
    log_step "Deploying containers on VPS..."

    local remote_host="${VPS_USER}@${VPS_HOST}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would run: docker compose pull"
        log_info "[DRY RUN] Would run: docker compose up -d"
        return
    fi

    # Pull latest images and deploy
    ssh -o ConnectTimeout=10 "$remote_host" "cd \"$DEPLOY_PATH\" && docker compose pull" || {
        log_error "Failed to pull Docker images"
        exit 1
    }

    ssh -o ConnectTimeout=10 "$remote_host" "cd \"$DEPLOY_PATH\" && docker compose up -d" || {
        log_error "Failed to start containers"
        exit 1
    }

    log_info "Containers deployed successfully"
}

cleanup_remote_secrets() {
    log_step "Cleaning up secrets on VPS..."

    local remote_host="${VPS_USER}@${VPS_HOST}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would securely delete: $DEPLOY_PATH/.env"
        return
    fi

    # Securely delete .env file on VPS
    # Note: shred may not be available on all systems, fall back to rm
    ssh -o ConnectTimeout=10 "$remote_host" "
        if command -v shred &> /dev/null; then
            shred -u \"$DEPLOY_PATH/.env\" 2>/dev/null || rm -f \"$DEPLOY_PATH/.env\"
        else
            rm -f \"$DEPLOY_PATH/.env\"
        fi
    " || {
        log_warn "Failed to clean up .env file on VPS - please delete manually"
    }

    log_info "Remote secrets cleaned up"
}

run_health_checks() {
    log_step "Running health checks..."

    local remote_host="${VPS_USER}@${VPS_HOST}"
    local max_retries=10
    local retry_delay=6

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would check container status"
        log_info "[DRY RUN] Would verify health endpoints"
        return
    fi

    # Wait for containers to start
    log_info "Waiting for containers to start..."
    sleep 5

    # Check container status
    log_info "Checking container status..."
    local container_status
    container_status=$(ssh -o ConnectTimeout=10 "$remote_host" "cd \"$DEPLOY_PATH\" && docker compose ps --format 'table {{.Name}}\t{{.Status}}'") || {
        log_error "Failed to get container status"
        return 1
    }
    echo "$container_status"

    # Check for any exited containers
    local exited_count
    exited_count=$(ssh -o ConnectTimeout=10 "$remote_host" "cd \"$DEPLOY_PATH\" && docker compose ps -a | grep -c 'exited' || true")
    if [[ "$exited_count" -gt 0 ]]; then
        log_error "Some containers have exited. Check logs with: ssh $remote_host 'cd $DEPLOY_PATH && docker compose logs'"
        return 1
    fi

    # Wait for health checks to pass
    log_info "Waiting for health checks to pass..."
    local healthy=false
    for i in $(seq 1 $max_retries); do
        local unhealthy_count
        unhealthy_count=$(ssh -o ConnectTimeout=10 "$remote_host" "cd \"$DEPLOY_PATH\" && docker compose ps | grep -E '(unhealthy|starting)' | wc -l || true")

        if [[ "$unhealthy_count" -eq 0 ]]; then
            healthy=true
            break
        fi

        log_info "Attempt $i/$max_retries: $unhealthy_count container(s) not yet healthy, waiting ${retry_delay}s..."
        sleep $retry_delay
    done

    if [[ "$healthy" != "true" ]]; then
        log_error "Health checks did not pass within timeout"
        log_info "Check container logs: ssh $remote_host 'cd $DEPLOY_PATH && docker compose logs --tail=50'"
        return 1
    fi

    # Show final status
    log_info "All containers healthy!"
    ssh -o ConnectTimeout=10 "$remote_host" "cd \"$DEPLOY_PATH\" && docker compose ps"

    # Show recent logs
    log_info "Recent logs (last 10 lines per service):"
    ssh -o ConnectTimeout=10 "$remote_host" "cd \"$DEPLOY_PATH\" && docker compose logs --tail=10"
}

save_deployment_info() {
    log_step "Saving deployment information..."

    local remote_host="${VPS_USER}@${VPS_HOST}"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would save deployment info"
        return
    fi

    # Save deployment metadata on VPS
    ssh -o ConnectTimeout=10 "$remote_host" "cat > \"$DEPLOY_PATH/.last_deploy\" <<EOF
TIMESTAMP=$timestamp
ENVIRONMENT=$ENVIRONMENT
IMAGE_TAG=$IMAGE_TAG
DEPLOYED_BY=$(whoami)@$(hostname)
EOF" || log_warn "Failed to save deployment info"

    log_info "Deployment info saved"
}

# Parse command line arguments
parse_args() {
    # First argument must be environment
    if [[ $# -eq 0 ]]; then
        log_error "Environment argument is required"
        echo ""
        show_help
    fi

    # Check for help flag first
    for arg in "$@"; do
        if [[ "$arg" == "--help" ]]; then
            show_help
        fi
    done

    ENVIRONMENT="$1"
    shift

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--host)
                VPS_HOST="$2"
                shift 2
                ;;
            -u|--user)
                VPS_USER="$2"
                shift 2
                ;;
            -p|--path)
                DEPLOY_PATH="$2"
                shift 2
                ;;
            -k|--key)
                AGE_KEY_FILE="$2"
                shift 2
                ;;
            -t|--tag)
                IMAGE_TAG="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-health)
                SKIP_HEALTH=true
                shift
                ;;
            --help)
                show_help
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                ;;
        esac
    done
}

# Main execution
main() {
    parse_args "$@"

    # Initialize deployment log
    DEPLOY_LOG="$PROJECT_ROOT/logs/deploy-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S).log"
    mkdir -p "$(dirname "$DEPLOY_LOG")"

    # Start logging
    exec > >(tee -a "$DEPLOY_LOG") 2>&1

    echo ""
    log_info "=========================================="
    log_info "ShopBuilder Deployment"
    log_info "=========================================="
    log_info "Environment: $ENVIRONMENT"
    log_info "VPS Host:    $VPS_HOST"
    log_info "VPS User:    $VPS_USER"
    log_info "Deploy Path: $DEPLOY_PATH"
    log_info "Image Tag:   $IMAGE_TAG"
    log_info "Dry Run:     $DRY_RUN"
    log_info "=========================================="
    echo ""

    check_requirements
    decrypt_secrets
    transfer_files
    deploy_containers
    cleanup_remote_secrets
    save_deployment_info

    if [[ "$SKIP_HEALTH" != "true" ]]; then
        run_health_checks || {
            log_error "Deployment completed but health checks failed"
            log_info "Consider running: ./scripts/rollback.sh $ENVIRONMENT"
            exit 1
        }
    fi

    echo ""
    log_info "=========================================="
    log_info "Deployment completed successfully!"
    log_info "=========================================="
    log_info "Environment: $ENVIRONMENT"
    log_info "Image Tag:   $IMAGE_TAG"
    log_info "Log File:    $DEPLOY_LOG"
    log_info "=========================================="
}

main "$@"

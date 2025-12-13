#!/usr/bin/env bash
#
# ShopBuilder Docker Compose Rollback Script
# Rolls back to a previous deployment version
#
# Usage:
#   ./scripts/rollback.sh <environment> [OPTIONS] [VERSION]
#
# Arguments:
#   environment         Target environment: staging or production
#   VERSION             Docker image tag to rollback to (optional)
#
# Options:
#   -h, --host          VPS hostname or IP address (or set VPS_HOST)
#   -u, --user          SSH user (default: root, or set VPS_USER)
#   -p, --path          Remote deployment path (default: /opt/shop-builder)
#   -k, --key           Age key file path (default: keys/<environment>.age.key)
#   -l, --list          List available image versions and recent deployments
#   -n, --count         Number of items to list (default: 10)
#   --dry-run           Show what would be done without executing
#   -y, --yes           Skip confirmation prompt
#   --help              Show this help message
#
# Environment Variables:
#   VPS_HOST            VPS hostname or IP address
#   VPS_USER            SSH user (default: root)
#   DEPLOY_PATH         Remote deployment path (default: /opt/shop-builder)
#   SOPS_AGE_KEY_FILE   Path to age private key (alternative to -k flag)
#
# Examples:
#   ./scripts/rollback.sh staging --list              # List available versions
#   ./scripts/rollback.sh production v1.2.2           # Rollback to specific version
#   ./scripts/rollback.sh production -y v1.2.2        # Rollback without confirmation

set -euo pipefail

# Script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
ENVIRONMENT=""
VERSION=""
VPS_HOST="${VPS_HOST:-}"
VPS_USER="${VPS_USER:-root}"
DEPLOY_PATH="${DEPLOY_PATH:-/opt/shop-builder}"
AGE_KEY_FILE=""
LIST_MODE=false
LIST_COUNT=10
DRY_RUN=false
SKIP_CONFIRM=false

# Temporary files
TEMP_ENV_FILE=""

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

show_help() {
    head -35 "$0" | grep "^#" | sed 's/^# \?//'
    exit 0
}

# Cleanup function
cleanup() {
    local exit_code=$?

    # Securely delete temporary env file
    if [[ -n "$TEMP_ENV_FILE" && -f "$TEMP_ENV_FILE" ]]; then
        if command -v shred &> /dev/null; then
            shred -u "$TEMP_ENV_FILE" 2>/dev/null || rm -f "$TEMP_ENV_FILE"
        else
            rm -f "$TEMP_ENV_FILE"
        fi
    fi

    exit $exit_code
}

trap cleanup EXIT

check_requirements() {
    log_step "Checking requirements..."

    # Check ssh is available
    if ! command -v ssh &> /dev/null; then
        log_error "SSH client is not installed."
        exit 1
    fi

    # Validate environment
    if [[ "$ENVIRONMENT" != "staging" && "$ENVIRONMENT" != "production" ]]; then
        log_error "Invalid environment: $ENVIRONMENT"
        log_info "Valid environments: staging, production"
        exit 1
    fi

    # Check VPS host is set
    if [[ -z "$VPS_HOST" ]]; then
        log_error "VPS host is required. Use -h flag or set VPS_HOST environment variable."
        exit 1
    fi

    log_info "Requirements satisfied"
}

check_secrets_requirements() {
    # Only needed if we're doing a full rollback (not just list)
    if ! command -v sops &> /dev/null; then
        log_error "SOPS is not installed."
        log_info "Install with: brew install sops (macOS) or see docs/secrets-management.md"
        exit 1
    fi

    # Validate VERSION format (alphanumeric, dots, dashes, underscores)
    if [[ ! "$VERSION" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        log_error "Invalid VERSION format: $VERSION"
        log_info "VERSION must contain only alphanumeric characters, dots, dashes, and underscores"
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
        exit 1
    fi

    # Check encrypted secrets file exists
    local secrets_file="$PROJECT_ROOT/secrets/${ENVIRONMENT}.enc.yaml"
    if [[ ! -f "$secrets_file" ]]; then
        log_error "Encrypted secrets file not found: $secrets_file"
        exit 1
    fi
}

list_deployments() {
    log_step "Fetching deployment information..."

    local remote_host="${VPS_USER}@${VPS_HOST}"

    echo ""
    echo -e "${CYAN}Last Deployment Info:${NC}"
    echo "====================="

    # Get last deployment info
    ssh -o ConnectTimeout=10 "$remote_host" "
        if [[ -f \"$DEPLOY_PATH/.last_deploy\" ]]; then
            cat \"$DEPLOY_PATH/.last_deploy\"
        else
            echo 'No deployment info found'
        fi
    " 2>/dev/null || echo "Unable to retrieve deployment info"

    echo ""
    echo -e "${CYAN}Current Running Containers:${NC}"
    echo "==========================="

    # Get current container versions
    ssh -o ConnectTimeout=10 "$remote_host" "
        cd \"$DEPLOY_PATH\" 2>/dev/null && docker compose ps --format 'table {{.Name}}\t{{.Image}}\t{{.Status}}' 2>/dev/null || echo 'No containers running'
    " 2>/dev/null || echo "Unable to retrieve container status"

    echo ""
    echo -e "${CYAN}Available Image Tags (from Docker Hub):${NC}"
    echo "========================================"
    echo "Note: Listing tags requires Docker Hub API access."
    echo "Check your container registry for available versions."
    echo ""

    # Try to get available tags from running containers
    ssh -o ConnectTimeout=10 "$remote_host" "
        docker images --format '{{.Repository}}:{{.Tag}}\t{{.CreatedAt}}' 2>/dev/null | grep -E 'shopbuilder|spring' | head -$LIST_COUNT || echo 'No local images found'
    " 2>/dev/null || echo "Unable to list images"

    echo ""
    echo -e "${CYAN}Recent Docker Compose History:${NC}"
    echo "=============================="

    # Check for any backup compose files or deployment history
    ssh -o ConnectTimeout=10 "$remote_host" "
        ls -la \"$DEPLOY_PATH\"/*.yml \"$DEPLOY_PATH\"/*.yaml 2>/dev/null || echo 'No compose files found'
        echo ''
        echo 'Container history (recent):'
        docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.CreatedAt}}' 2>/dev/null | head -$((LIST_COUNT + 1)) || echo 'No container history'
    " 2>/dev/null || echo "Unable to retrieve history"

    echo ""
    echo -e "${CYAN}To rollback, run:${NC}"
    echo "  $0 $ENVIRONMENT <VERSION>"
    echo ""
    echo "Example:"
    echo "  $0 $ENVIRONMENT v1.2.2"
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
        exit 1
    fi

    # Add image tag override for rollback
    {
        echo ""
        echo "# Rollback overrides"
        echo "FRONTEND_IMAGE=shopbuilder/frontend:${VERSION}"
        echo "SPRING_API_IMAGE=shopbuilder/spring-api:${VERSION}"
        echo "SPRING_WORKERS_IMAGE=shopbuilder/spring-workers:${VERSION}"
    } >> "$TEMP_ENV_FILE"

    log_info "Secrets decrypted with rollback version: $VERSION"
}

confirm_rollback() {
    if [[ "$SKIP_CONFIRM" == "true" ]]; then
        return 0
    fi

    echo ""
    log_warn "This will rollback $ENVIRONMENT to version: $VERSION"
    log_warn "Current containers will be stopped and replaced."
    echo ""

    read -p "Are you sure you want to proceed? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Rollback cancelled."
        exit 0
    fi
}

perform_rollback() {
    log_step "Performing rollback to version: $VERSION"

    local remote_host="${VPS_USER}@${VPS_HOST}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would transfer .env file with version $VERSION"
        log_info "[DRY RUN] Would run: docker compose pull"
        log_info "[DRY RUN] Would run: docker compose up -d"
        log_info "[DRY RUN] Would clean up secrets"
        return
    fi

    # Transfer .env file
    log_info "Transferring configuration..."
    scp -o ConnectTimeout=10 "$TEMP_ENV_FILE" "$remote_host:$DEPLOY_PATH/.env" || {
        log_error "Failed to transfer .env file"
        exit 1
    }

    # Stop current containers
    log_info "Stopping current containers..."
    ssh -o ConnectTimeout=10 "$remote_host" "cd \"$DEPLOY_PATH\" && docker compose down" || {
        log_warn "Failed to stop containers gracefully, continuing..."
    }

    # Pull specified version
    log_info "Pulling version $VERSION..."
    ssh -o ConnectTimeout=10 "$remote_host" "cd \"$DEPLOY_PATH\" && docker compose pull" || {
        log_error "Failed to pull images for version $VERSION"
        log_info "The specified version may not exist. Use --list to see available versions."
        exit 1
    }

    # Start containers with new version
    log_info "Starting containers..."
    ssh -o ConnectTimeout=10 "$remote_host" "cd \"$DEPLOY_PATH\" && docker compose up -d" || {
        log_error "Failed to start containers"
        exit 1
    }

    # Clean up secrets on VPS
    log_info "Cleaning up secrets on VPS..."
    ssh -o ConnectTimeout=10 "$remote_host" "
        if command -v shred &> /dev/null; then
            shred -u \"$DEPLOY_PATH/.env\" 2>/dev/null || rm -f \"$DEPLOY_PATH/.env\"
        else
            rm -f \"$DEPLOY_PATH/.env\"
        fi
    " || log_warn "Failed to clean up secrets"

    # Save rollback info
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    ssh -o ConnectTimeout=10 "$remote_host" "cat > \"$DEPLOY_PATH/.last_deploy\" <<EOF
TIMESTAMP=$timestamp
ENVIRONMENT=$ENVIRONMENT
IMAGE_TAG=$VERSION
DEPLOYED_BY=$(whoami)@$(hostname)
ROLLBACK=true
EOF" || log_warn "Failed to save rollback info"

    log_info "Rollback completed"
}

verify_rollback() {
    log_step "Verifying rollback..."

    local remote_host="${VPS_USER}@${VPS_HOST}"
    local max_retries=10
    local retry_delay=6

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify container health"
        return
    fi

    # Wait for containers to start
    sleep 5

    # Check container status
    log_info "Checking container status..."
    ssh -o ConnectTimeout=10 "$remote_host" "cd \"$DEPLOY_PATH\" && docker compose ps"

    # Wait for health checks
    log_info "Waiting for health checks..."
    local healthy=false
    for i in $(seq 1 $max_retries); do
        local unhealthy_count
        unhealthy_count=$(ssh -o ConnectTimeout=10 "$remote_host" "cd \"$DEPLOY_PATH\" && docker compose ps | grep -E '(unhealthy|starting)' | wc -l || true")

        if [[ "$unhealthy_count" -eq 0 ]]; then
            healthy=true
            break
        fi

        log_info "Attempt $i/$max_retries: Waiting for containers to become healthy..."
        sleep $retry_delay
    done

    if [[ "$healthy" != "true" ]]; then
        log_error "Health checks did not pass within timeout"
        log_info "Check logs: ssh $remote_host 'cd $DEPLOY_PATH && docker compose logs --tail=50'"
        return 1
    fi

    log_info "All containers healthy!"

    # Show current image versions
    echo ""
    log_info "Running containers:"
    ssh -o ConnectTimeout=10 "$remote_host" "cd \"$DEPLOY_PATH\" && docker compose ps --format 'table {{.Name}}\t{{.Image}}\t{{.Status}}'"
}

# Parse command line arguments
parse_args() {
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
            -l|--list)
                LIST_MODE=true
                shift
                ;;
            -n|--count)
                LIST_COUNT="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRM=true
                shift
                ;;
            --help)
                show_help
                ;;
            -*)
                log_error "Unknown option: $1"
                show_help
                ;;
            *)
                VERSION="$1"
                shift
                ;;
        esac
    done
}

# Main execution
main() {
    parse_args "$@"

    echo ""
    log_info "=========================================="
    log_info "ShopBuilder Rollback"
    log_info "=========================================="
    log_info "Environment: $ENVIRONMENT"
    log_info "VPS Host:    $VPS_HOST"

    check_requirements

    if [[ "$LIST_MODE" == "true" ]] || [[ -z "$VERSION" ]]; then
        list_deployments
        exit 0
    fi

    log_info "Target Ver:  $VERSION"
    log_info "=========================================="
    echo ""

    check_secrets_requirements
    confirm_rollback
    decrypt_secrets
    perform_rollback
    verify_rollback

    echo ""
    log_info "=========================================="
    log_info "Rollback completed successfully!"
    log_info "=========================================="
    log_info "Environment: $ENVIRONMENT"
    log_info "Version:     $VERSION"
    log_info "=========================================="
}

main "$@"

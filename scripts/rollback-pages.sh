#!/usr/bin/env bash
#
# Cloudflare Pages Rollback Script
# Rollback to a previous deployment on Cloudflare Pages
#
# Usage:
#   ./scripts/rollback-pages.sh [OPTIONS] [DEPLOYMENT_ID]
#
# Options:
#   -p, --project       Cloudflare Pages project name (required or set CLOUDFLARE_PAGES_PROJECT)
#   -l, --list          List recent deployments instead of rolling back
#   -n, --count         Number of deployments to list (default: 10)
#   -h, --help          Show this help message
#
# Arguments:
#   DEPLOYMENT_ID       ID of the deployment to rollback to
#                       If not provided with -l flag, lists deployments
#
# Environment Variables:
#   CLOUDFLARE_API_TOKEN       Cloudflare API token (required)
#   CLOUDFLARE_ACCOUNT_ID      Cloudflare account ID (required)
#   CLOUDFLARE_PAGES_PROJECT   Default project name
#
# Examples:
#   ./scripts/rollback-pages.sh -l                    # List deployments
#   ./scripts/rollback-pages.sh -l -n 20              # List 20 deployments
#   ./scripts/rollback-pages.sh abc123def456          # Rollback to deployment
#   ./scripts/rollback-pages.sh -p myproject abc123   # Rollback specific project

set -euo pipefail

# Default values
PROJECT_NAME="${CLOUDFLARE_PAGES_PROJECT:-}"
LIST_MODE=false
LIST_COUNT=10
DEPLOYMENT_ID=""

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
    head -32 "$0" | grep "^#" | sed 's/^# \?//'
    exit 0
}

check_requirements() {
    log_step "Checking requirements..."

    if ! command -v wrangler &> /dev/null; then
        log_error "Wrangler CLI is not installed."
        log_info "Install with: npm install -g wrangler"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        log_warn "jq is not installed. Output formatting may be limited."
    fi

    if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
        log_error "CLOUDFLARE_API_TOKEN environment variable is required"
        exit 1
    fi

    if [[ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]]; then
        log_error "CLOUDFLARE_ACCOUNT_ID environment variable is required"
        exit 1
    fi

    if [[ -z "$PROJECT_NAME" ]]; then
        log_error "Project name is required. Use -p flag or set CLOUDFLARE_PAGES_PROJECT"
        exit 1
    fi
}

list_deployments() {
    log_step "Listing recent deployments for $PROJECT_NAME..."

    echo ""
    echo -e "${CYAN}Recent Deployments:${NC}"
    echo "==================="

    # Use Cloudflare API to list deployments with better formatting
    local api_url="https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects/${PROJECT_NAME}/deployments"

    local response
    response=$(curl -s -X GET "$api_url?per_page=$LIST_COUNT" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json")

    if command -v jq &> /dev/null; then
        local success
        success=$(echo "$response" | jq -r '.success')

        if [[ "$success" != "true" ]]; then
            local error_msg
            error_msg=$(echo "$response" | jq -r '.errors[0].message // "Unknown error"')
            log_error "API error: $error_msg"
            exit 1
        fi

        echo "$response" | jq -r '.result[] | "\(.id)\t\(.environment)\t\(.created_on)\t\(.deployment_trigger.metadata.branch // "N/A")\t\(.deployment_trigger.metadata.commit_message // "N/A" | .[0:50])"' | \
        while IFS=$'\t' read -r id env created branch msg; do
            local env_color
            if [[ "$env" == "production" ]]; then
                env_color="${GREEN}"
            else
                env_color="${YELLOW}"
            fi
            printf "%-36s ${env_color}%-12s${NC} %-25s %-15s %s\n" "$id" "$env" "$created" "$branch" "$msg"
        done
    else
        # Fallback to wrangler CLI
        wrangler pages deployment list --project-name="$PROJECT_NAME" | head -$((LIST_COUNT + 5))
    fi

    echo ""
    echo -e "${CYAN}To rollback, run:${NC}"
    echo "  $0 -p $PROJECT_NAME <DEPLOYMENT_ID>"
}

rollback() {
    log_step "Rolling back to deployment: $DEPLOYMENT_ID"

    log_warn "This will make deployment $DEPLOYMENT_ID the active production deployment."
    echo ""

    # Confirm rollback
    read -p "Are you sure you want to proceed? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Rollback cancelled."
        exit 0
    fi

    # Perform rollback via Cloudflare API
    local api_url="https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/pages/projects/${PROJECT_NAME}/deployments/${DEPLOYMENT_ID}/rollback"

    local response
    response=$(curl -s -X POST "$api_url" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json")

    if command -v jq &> /dev/null; then
        local success
        success=$(echo "$response" | jq -r '.success')

        if [[ "$success" == "true" ]]; then
            log_info "Rollback successful!"

            local new_deployment_id
            new_deployment_id=$(echo "$response" | jq -r '.result.id')
            log_info "New deployment ID: $new_deployment_id"
        else
            local error_msg
            error_msg=$(echo "$response" | jq -r '.errors[0].message // "Unknown error"')
            log_error "Rollback failed: $error_msg"
            exit 1
        fi
    else
        echo "$response"
        log_info "Rollback request sent. Check Cloudflare dashboard for status."
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project)
            PROJECT_NAME="$2"
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
        -h|--help)
            show_help
            ;;
        -*)
            log_error "Unknown option: $1"
            show_help
            ;;
        *)
            DEPLOYMENT_ID="$1"
            shift
            ;;
    esac
done

# Main execution
main() {
    check_requirements

    if [[ "$LIST_MODE" == "true" ]] || [[ -z "$DEPLOYMENT_ID" ]]; then
        list_deployments
    else
        rollback
    fi
}

main

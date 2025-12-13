#!/usr/bin/env bash
#
# Cloudflare Pages Deployment Script
# Deploys Hugo site to Cloudflare Pages using Wrangler CLI
#
# Usage:
#   ./scripts/deploy-pages.sh [OPTIONS]
#
# Options:
#   -p, --project       Cloudflare Pages project name (required or set CLOUDFLARE_PAGES_PROJECT)
#   -d, --directory     Directory to deploy (default: public)
#   -b, --branch        Git branch name for deployment (default: current branch)
#   -c, --commit-hash   Git commit hash (default: current HEAD)
#   -m, --commit-msg    Git commit message (default: current commit message)
#   --production        Deploy as production (default for main branch)
#   --preview           Deploy as preview
#   -h, --help          Show this help message
#
# Environment Variables:
#   CLOUDFLARE_API_TOKEN       Cloudflare API token (required)
#   CLOUDFLARE_ACCOUNT_ID      Cloudflare account ID (required)
#   CLOUDFLARE_PAGES_PROJECT   Default project name
#
# Examples:
#   ./scripts/deploy-pages.sh -p staticshop-marketing
#   ./scripts/deploy-pages.sh -p staticshop-marketing -d public --production
#   CLOUDFLARE_PAGES_PROJECT=staticshop-marketing ./scripts/deploy-pages.sh

set -euo pipefail

# Default values
PROJECT_NAME="${CLOUDFLARE_PAGES_PROJECT:-}"
DEPLOY_DIRECTORY="public"
BRANCH="${GITHUB_REF_NAME:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'main')}"
COMMIT_HASH="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo '')}"
COMMIT_MSG="${GITHUB_COMMIT_MESSAGE:-$(git log -1 --format=%s 2>/dev/null || echo 'Manual deployment')}"
PRODUCTION_DEPLOY=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
    head -30 "$0" | grep "^#" | sed 's/^# \?//'
    exit 0
}

check_requirements() {
    log_step "Checking requirements..."

    # Check wrangler is installed
    if ! command -v wrangler &> /dev/null; then
        log_error "Wrangler CLI is not installed."
        log_info "Install with: npm install -g wrangler"
        exit 1
    fi

    local wrangler_version
    wrangler_version=$(wrangler --version 2>/dev/null | head -1)
    log_info "Wrangler version: $wrangler_version"

    # Check required environment variables
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

    # Check deploy directory exists
    if [[ ! -d "$DEPLOY_DIRECTORY" ]]; then
        log_error "Deploy directory not found: $DEPLOY_DIRECTORY"
        log_info "Run ./scripts/hugo-build.sh first to build the site"
        exit 1
    fi

    if [[ ! -f "$DEPLOY_DIRECTORY/index.html" ]]; then
        log_error "index.html not found in deploy directory"
        exit 1
    fi
}

determine_deployment_type() {
    # Determine if this is a production or preview deployment
    if [[ -n "$PRODUCTION_DEPLOY" ]]; then
        return
    fi

    if [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
        PRODUCTION_DEPLOY="true"
        log_info "Deploying as production (branch: $BRANCH)"
    else
        PRODUCTION_DEPLOY="false"
        log_info "Deploying as preview (branch: $BRANCH)"
    fi
}

deploy() {
    log_step "Deploying to Cloudflare Pages..."

    local wrangler_args=(
        "pages" "deploy" "$DEPLOY_DIRECTORY"
        "--project-name=$PROJECT_NAME"
    )

    if [[ -n "$BRANCH" ]]; then
        wrangler_args+=("--branch=$BRANCH")
    fi

    if [[ -n "$COMMIT_HASH" ]]; then
        wrangler_args+=("--commit-hash=$COMMIT_HASH")
    fi

    if [[ -n "$COMMIT_MSG" ]]; then
        wrangler_args+=("--commit-message=$COMMIT_MSG")
    fi

    log_info "Running: wrangler ${wrangler_args[*]}"

    # Run deployment and capture output
    local output
    if output=$(wrangler "${wrangler_args[@]}" 2>&1); then
        echo "$output"

        # Extract deployment URL from output
        local deploy_url
        deploy_url=$(echo "$output" | grep -oP 'https://[^\s]+\.pages\.dev' | head -1 || true)

        if [[ -n "$deploy_url" ]]; then
            log_info "Deployment URL: $deploy_url"
        fi

        # For production deployments, also show custom domain
        if [[ "$PRODUCTION_DEPLOY" == "true" ]]; then
            log_info "Production deployment complete!"
            log_info "Custom domain: https://staticshop.io (if configured)"
        else
            log_info "Preview deployment complete!"
        fi
    else
        log_error "Deployment failed!"
        echo "$output" >&2
        exit 1
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project)
            PROJECT_NAME="$2"
            shift 2
            ;;
        -d|--directory)
            DEPLOY_DIRECTORY="$2"
            shift 2
            ;;
        -b|--branch)
            BRANCH="$2"
            shift 2
            ;;
        -c|--commit-hash)
            COMMIT_HASH="$2"
            shift 2
            ;;
        -m|--commit-msg)
            COMMIT_MSG="$2"
            shift 2
            ;;
        --production)
            PRODUCTION_DEPLOY="true"
            shift
            ;;
        --preview)
            PRODUCTION_DEPLOY="false"
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            ;;
    esac
done

# Main execution
main() {
    log_info "Starting Cloudflare Pages deployment..."
    log_info "Project: $PROJECT_NAME"
    log_info "Directory: $DEPLOY_DIRECTORY"
    log_info "Branch: $BRANCH"

    check_requirements
    determine_deployment_type
    deploy

    log_info "Deployment completed successfully!"
}

main

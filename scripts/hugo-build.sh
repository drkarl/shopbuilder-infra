#!/usr/bin/env bash
#
# Hugo Build Script
# Builds the Hugo marketing site with minification
#
# Usage:
#   ./scripts/hugo-build.sh [OPTIONS]
#
# Options:
#   -e, --environment   Build environment (development, staging, production)
#   -d, --destination   Output directory (default: public)
#   -b, --base-url      Override base URL
#   -v, --verbose       Enable verbose output
#   -h, --help          Show this help message
#
# Environment Variables:
#   HUGO_ENV            Build environment (default: production)
#   HUGO_BASEURL        Base URL for the site
#   HUGO_VERSION        Hugo version to use (for CI)
#
# Examples:
#   ./scripts/hugo-build.sh
#   ./scripts/hugo-build.sh -e staging
#   ./scripts/hugo-build.sh -b "https://preview.staticshop.io"

set -euo pipefail

# Default values
ENVIRONMENT="${HUGO_ENV:-production}"
DESTINATION="public"
BASE_URL="${HUGO_BASEURL:-}"
VERBOSE=false
HUGO_MIN_VERSION="0.120.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

show_help() {
    head -30 "$0" | grep "^#" | sed 's/^# \?//'
    exit 0
}

check_hugo() {
    if ! command -v hugo &> /dev/null; then
        log_error "Hugo is not installed. Please install Hugo first."
        log_info "See: https://gohugo.io/installation/"
        exit 1
    fi

    local version
    version=$(hugo version | grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    log_info "Hugo version: $version"

    # Version comparison (basic)
    if [[ "$(printf '%s\n' "$HUGO_MIN_VERSION" "$version" | sort -V | head -n1)" != "$HUGO_MIN_VERSION" ]]; then
        log_warn "Hugo version $version is older than recommended ($HUGO_MIN_VERSION)"
    fi
}

clean_destination() {
    if [[ -d "$DESTINATION" ]]; then
        log_info "Cleaning previous build..."
        rm -rf "$DESTINATION"
    fi
}

build_site() {
    log_info "Building Hugo site for environment: $ENVIRONMENT"

    local hugo_args=(
        "--minify"
        "--destination" "$DESTINATION"
        "--environment" "$ENVIRONMENT"
    )

    if [[ -n "$BASE_URL" ]]; then
        hugo_args+=("--baseURL" "$BASE_URL")
    fi

    if [[ "$VERBOSE" == "true" ]]; then
        hugo_args+=("--verbose")
    fi

    if [[ "$ENVIRONMENT" == "production" ]]; then
        hugo_args+=("--gc")
    fi

    log_info "Running: hugo ${hugo_args[*]}"
    hugo "${hugo_args[@]}"

    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Hugo build failed with exit code $exit_code"
        exit $exit_code
    fi
}

verify_build() {
    if [[ ! -d "$DESTINATION" ]]; then
        log_error "Build directory not found: $DESTINATION"
        exit 1
    fi

    if [[ ! -f "$DESTINATION/index.html" ]]; then
        log_error "index.html not found in build output"
        exit 1
    fi

    local file_count
    file_count=$(find "$DESTINATION" -type f | wc -l)
    log_info "Build complete: $file_count files in $DESTINATION/"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -d|--destination)
            DESTINATION="$2"
            shift 2
            ;;
        -b|--base-url)
            BASE_URL="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
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
    log_info "Starting Hugo build process..."

    check_hugo
    clean_destination
    build_site
    verify_build

    log_info "Hugo build completed successfully!"
}

main

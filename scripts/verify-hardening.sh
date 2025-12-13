#!/usr/bin/env bash
#
# VM Hardening Verification Script
# Verifies security hardening settings on VPS instances
#
# Usage:
#   ./scripts/verify-hardening.sh [OPTIONS]
#
# Options:
#   --ssh-port PORT    Expected SSH port (default: 22)
#   --ssh-user USER    Expected SSH user (default: deploy)
#   --json             Output results as JSON
#   --quiet            Only output failures
#   -h, --help         Show this help message
#
# Exit Codes:
#   0 - All checks passed
#   1 - One or more checks failed
#   2 - Script error

set -euo pipefail

# Default values
SSH_PORT="22"
SSH_USER="deploy"
OUTPUT_JSON="false"
QUIET="false"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Results tracking
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
declare -a RESULTS=()

log_pass() {
    ((PASS_COUNT++))
    RESULTS+=("PASS|$1")
    [[ "$QUIET" != "true" ]] && echo -e "${GREEN}[PASS]${NC} $1"
}

log_fail() {
    ((FAIL_COUNT++))
    RESULTS+=("FAIL|$1")
    echo -e "${RED}[FAIL]${NC} $1"
}

log_warn() {
    ((WARN_COUNT++))
    RESULTS+=("WARN|$1")
    [[ "$QUIET" != "true" ]] && echo -e "${YELLOW}[WARN]${NC} $1"
}

log_info() {
    [[ "$QUIET" != "true" ]] && echo -e "${BLUE}[INFO]${NC} $1"
}

show_help() {
    head -20 "$0" | grep "^#" | sed 's/^# \?//'
    exit 0
}

output_json() {
    echo "{"
    echo "  \"summary\": {"
    echo "    \"passed\": $PASS_COUNT,"
    echo "    \"failed\": $FAIL_COUNT,"
    echo "    \"warnings\": $WARN_COUNT,"
    echo "    \"total\": $((PASS_COUNT + FAIL_COUNT + WARN_COUNT))"
    echo "  },"
    echo "  \"results\": ["
    local first=true
    for result in "${RESULTS[@]}"; do
        IFS='|' read -r status message <<< "$result"
        [[ "$first" != "true" ]] && echo ","
        first=false
        echo -n "    {\"status\": \"$status\", \"message\": \"$message\"}"
    done
    echo ""
    echo "  ]"
    echo "}"
}

#------------------------------------------------------------------------------
# SSH Checks
#------------------------------------------------------------------------------
check_ssh() {
    log_info "Checking SSH configuration..."

    local sshd_config="/etc/ssh/sshd_config"

    # Check SSH service is running
    if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
        log_pass "SSH service is running"
    else
        log_fail "SSH service is not running"
    fi

    if [[ ! -f "$sshd_config" ]]; then
        log_fail "SSH config file not found: $sshd_config"
        return
    fi

    # Check root login disabled
    if grep -qE "^PermitRootLogin\s+no" "$sshd_config"; then
        log_pass "Root login is disabled"
    else
        log_fail "Root login is NOT disabled"
    fi

    # Check password authentication disabled
    if grep -qE "^PasswordAuthentication\s+no" "$sshd_config"; then
        log_pass "Password authentication is disabled"
    else
        log_fail "Password authentication is NOT disabled"
    fi

    # Check pubkey authentication enabled
    if grep -qE "^PubkeyAuthentication\s+yes" "$sshd_config"; then
        log_pass "Public key authentication is enabled"
    else
        log_fail "Public key authentication is NOT enabled"
    fi

    # Check SSH port (defaults to 22 if not explicitly configured)
    local current_port
    current_port=$(grep -E "^Port\s+" "$sshd_config" | awk '{print $2}')
    if [[ -z "$current_port" ]]; then
        current_port="22"
    fi
    if [[ "$current_port" == "$SSH_PORT" ]]; then
        log_pass "SSH port is set to $SSH_PORT"
    else
        log_warn "SSH port is $current_port (expected $SSH_PORT)"
    fi

    # Check AllowUsers
    if grep -qE "^AllowUsers\s+" "$sshd_config"; then
        local allowed_users
        allowed_users=$(grep -E "^AllowUsers\s+" "$sshd_config" | cut -d' ' -f2-)
        if echo "$allowed_users" | grep -q "$SSH_USER"; then
            log_pass "AllowUsers includes $SSH_USER"
        else
            log_warn "AllowUsers does not include $SSH_USER (current: $allowed_users)"
        fi
    else
        log_warn "AllowUsers is not configured"
    fi

    # Check X11Forwarding disabled
    if grep -qE "^X11Forwarding\s+no" "$sshd_config"; then
        log_pass "X11 forwarding is disabled"
    else
        log_warn "X11 forwarding is NOT disabled"
    fi

    # Check MaxAuthTries
    local max_tries
    max_tries=$(grep -E "^MaxAuthTries\s+" "$sshd_config" | awk '{print $2}' || echo "")
    if [[ -n "$max_tries" && "$max_tries" -le 5 ]]; then
        log_pass "MaxAuthTries is set to $max_tries"
    else
        log_warn "MaxAuthTries is not set or too high"
    fi
}

#------------------------------------------------------------------------------
# Firewall Checks
#------------------------------------------------------------------------------
check_firewall() {
    log_info "Checking firewall configuration..."

    # Check if UFW is installed
    if ! command -v ufw &> /dev/null; then
        log_fail "UFW is not installed"
        return
    fi

    # Check UFW status
    if ufw status | grep -q "Status: active"; then
        log_pass "UFW firewall is active"
    else
        log_fail "UFW firewall is NOT active"
        return
    fi

    # Check default policies
    if ufw status verbose | grep -q "Default: deny (incoming)"; then
        log_pass "Default incoming policy is deny"
    else
        log_fail "Default incoming policy is NOT deny"
    fi

    if ufw status verbose | grep -q "Default: allow (outgoing)"; then
        log_pass "Default outgoing policy is allow"
    else
        log_warn "Default outgoing policy is not allow"
    fi

    # Check SSH rule exists
    if ufw status | grep -qE "$SSH_PORT/tcp\s+ALLOW"; then
        log_pass "SSH port $SSH_PORT is allowed"
    else
        log_warn "SSH port $SSH_PORT rule not found"
    fi
}

#------------------------------------------------------------------------------
# fail2ban Checks
#------------------------------------------------------------------------------
check_fail2ban() {
    log_info "Checking fail2ban configuration..."

    # Check if fail2ban is installed
    if ! command -v fail2ban-client &> /dev/null; then
        log_fail "fail2ban is not installed"
        return
    fi

    # Check fail2ban service
    if systemctl is-active --quiet fail2ban; then
        log_pass "fail2ban service is running"
    else
        log_fail "fail2ban service is NOT running"
        return
    fi

    # Check sshd jail is enabled
    if fail2ban-client status sshd &>/dev/null; then
        log_pass "fail2ban sshd jail is enabled"

        # Get ban statistics
        local banned
        banned=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | awk '{print $NF}')
        log_info "Currently banned IPs: $banned"
    else
        log_fail "fail2ban sshd jail is NOT enabled"
    fi
}

#------------------------------------------------------------------------------
# Unattended Upgrades Checks
#------------------------------------------------------------------------------
check_unattended_upgrades() {
    log_info "Checking unattended upgrades..."

    # Check if package is installed
    if dpkg -l | grep -q "unattended-upgrades"; then
        log_pass "unattended-upgrades is installed"
    else
        log_fail "unattended-upgrades is NOT installed"
        return
    fi

    # Check service is enabled
    if systemctl is-enabled --quiet unattended-upgrades 2>/dev/null; then
        log_pass "unattended-upgrades service is enabled"
    else
        log_fail "unattended-upgrades service is NOT enabled"
    fi

    # Check configuration exists
    if [[ -f /etc/apt/apt.conf.d/20auto-upgrades ]]; then
        if grep -q 'APT::Periodic::Unattended-Upgrade "1"' /etc/apt/apt.conf.d/20auto-upgrades; then
            log_pass "Automatic upgrades are enabled"
        else
            log_warn "Automatic upgrades may not be enabled"
        fi
    else
        log_warn "Auto-upgrades config not found"
    fi
}

#------------------------------------------------------------------------------
# Docker Checks
#------------------------------------------------------------------------------
check_docker() {
    log_info "Checking Docker security configuration..."

    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        log_info "Docker is not installed, skipping Docker checks"
        return
    fi

    # Check Docker service
    if systemctl is-active --quiet docker; then
        log_pass "Docker service is running"
    else
        log_warn "Docker service is not running"
        return
    fi

    local docker_config="/etc/docker/daemon.json"

    if [[ ! -f "$docker_config" ]]; then
        log_warn "Docker daemon.json not found"
        return
    fi

    # Check userns-remap
    if grep -q '"userns-remap"' "$docker_config"; then
        log_pass "Docker user namespace remapping is configured"
    else
        log_warn "Docker user namespace remapping is NOT configured"
    fi

    # Check live-restore
    if grep -q '"live-restore": true' "$docker_config"; then
        log_pass "Docker live-restore is enabled"
    else
        log_warn "Docker live-restore is NOT enabled"
    fi

    # Check no-new-privileges
    if grep -q '"no-new-privileges": true' "$docker_config"; then
        log_pass "Docker no-new-privileges is enabled"
    else
        log_warn "Docker no-new-privileges is NOT enabled"
    fi

    # Check log configuration
    if grep -q '"log-driver": "json-file"' "$docker_config"; then
        log_pass "Docker logging is configured"
    else
        log_warn "Docker logging may not be properly configured"
    fi
}

#------------------------------------------------------------------------------
# Log Rotation Checks
#------------------------------------------------------------------------------
check_logrotate() {
    log_info "Checking log rotation..."

    # Check if logrotate is installed
    if command -v logrotate &> /dev/null; then
        log_pass "logrotate is installed"
    else
        log_fail "logrotate is NOT installed"
        return
    fi

    # Check syslog rotation
    if [[ -f /etc/logrotate.d/syslog ]] || [[ -f /etc/logrotate.d/rsyslog ]]; then
        log_pass "System log rotation is configured"
    else
        log_warn "System log rotation may not be configured"
    fi
}

#------------------------------------------------------------------------------
# System Checks
#------------------------------------------------------------------------------
check_system() {
    log_info "Checking system security..."

    # Check for unnecessary services
    local unnecessary_services=("telnet" "rsh" "rlogin" "rexec" "finger")
    for service in "${unnecessary_services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_fail "Unnecessary service running: $service"
        fi
    done
    log_pass "No unnecessary legacy services running"

    # Check kernel hardening (if available)
    if [[ -f /proc/sys/kernel/randomize_va_space ]]; then
        local aslr
        aslr=$(cat /proc/sys/kernel/randomize_va_space)
        if [[ "$aslr" == "2" ]]; then
            log_pass "ASLR is fully enabled"
        else
            log_warn "ASLR may not be fully enabled (value: $aslr)"
        fi
    fi
}

#------------------------------------------------------------------------------
# Parse Arguments
#------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        --ssh-port)
            SSH_PORT="$2"
            shift 2
            ;;
        --ssh-user)
            SSH_USER="$2"
            shift 2
            ;;
        --json)
            OUTPUT_JSON="true"
            QUIET="true"
            shift
            ;;
        --quiet)
            QUIET="true"
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_help
            ;;
    esac
done

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------
main() {
    [[ "$QUIET" != "true" ]] && echo "=========================================="
    [[ "$QUIET" != "true" ]] && echo "VM Hardening Verification"
    [[ "$QUIET" != "true" ]] && echo "=========================================="
    [[ "$QUIET" != "true" ]] && echo ""

    check_ssh
    [[ "$QUIET" != "true" ]] && echo ""

    check_firewall
    [[ "$QUIET" != "true" ]] && echo ""

    check_fail2ban
    [[ "$QUIET" != "true" ]] && echo ""

    check_unattended_upgrades
    [[ "$QUIET" != "true" ]] && echo ""

    check_docker
    [[ "$QUIET" != "true" ]] && echo ""

    check_logrotate
    [[ "$QUIET" != "true" ]] && echo ""

    check_system
    [[ "$QUIET" != "true" ]] && echo ""

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        output_json
        # Exit with appropriate code based on failures
        if [[ $FAIL_COUNT -gt 0 ]]; then
            exit 1
        else
            exit 0
        fi
    else
        echo "=========================================="
        echo "Summary"
        echo "=========================================="
        echo -e "${GREEN}Passed:${NC}   $PASS_COUNT"
        echo -e "${RED}Failed:${NC}   $FAIL_COUNT"
        echo -e "${YELLOW}Warnings:${NC} $WARN_COUNT"
        echo ""

        if [[ $FAIL_COUNT -gt 0 ]]; then
            echo -e "${RED}Some checks failed! Review the failures above.${NC}"
            exit 1
        elif [[ $WARN_COUNT -gt 0 ]]; then
            echo -e "${YELLOW}All critical checks passed, but there are warnings to review.${NC}"
            exit 0
        else
            echo -e "${GREEN}All checks passed!${NC}"
            exit 0
        fi
    fi
}

main

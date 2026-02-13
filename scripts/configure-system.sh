#!/bin/bash
set -e

source "$SCRIPT_DIR/scripts/functions.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/functions.sh"

configure_system() {
    log "Configuring system settings..."

    # -------------------------------------------------
    # Core networking (required for WireGuard)
    # -------------------------------------------------
    log "Configuring IP forwarding..."
    apply_sysctl_param net.ipv4.ip_forward 1

    # -------------------------------------------------
    # High-connection proxy hardening
    # -------------------------------------------------
    log "Applying network and resource hardening settings..."

    # File descriptor capacity (system-wide)
    apply_sysctl_param fs.file-max 200000

    # Network backlog tuning
    apply_sysctl_param net.core.somaxconn 65535
    apply_sysctl_param net.core.netdev_max_backlog 16384

    # TCP tuning
    apply_sysctl_param net.ipv4.tcp_max_syn_backlog 8192
    apply_sysctl_param net.ipv4.tcp_synack_retries 3
    apply_sysctl_param net.ipv4.tcp_syncookies 1

    # Ephemeral port range
    apply_sysctl_param net.ipv4.ip_local_port_range "10240 65535"

    # Conntrack table (important for NAT + WireGuard + proxy)
    apply_sysctl_param net.netfilter.nf_conntrack_max 262144

    # Reduce TIME_WAIT buildup
    apply_sysctl_param net.ipv4.tcp_fin_timeout 15
    apply_sysctl_param net.ipv4.tcp_tw_reuse 1

    log "Sysctl parameters configured."

    # -------------------------------------------------
    # Apply sysctl settings
    # -------------------------------------------------
    log "Applying sysctl settings..."
    if sysctl --system > /dev/null 2>&1; then
        log "Sysctl settings applied successfully"
    else
        sysctl -p /etc/sysctl.conf > /dev/null 2>&1 || true
        warn "Used fallback method to apply sysctl settings"
    fi

    # -------------------------------------------------
    # Verify IP forwarding
    # -------------------------------------------------
    if [ "$(cat /proc/sys/net/ipv4/ip_forward)" -eq 1 ]; then
        log "IP forwarding is enabled (net.ipv4.ip_forward=1)"
    else
        warn "IP forwarding is not enabled. Attempting temporary enable..."
        echo 1 > /proc/sys/net/ipv4/ip_forward
        if [ "$(cat /proc/sys/net/ipv4/ip_forward)" -eq 1 ]; then
            log "Temporarily enabled IP forwarding"
        else
            error "Failed to enable IP forwarding. WireGuard may not work properly."
            return 1
        fi
    fi

    log "System configuration completed successfully."
    return 0
}

configure_system
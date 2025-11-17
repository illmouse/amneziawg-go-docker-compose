#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/functions.sh"

configure_system() {
    log "Configuring system settings..."
    
    # Configure IP forwarding
    log "Configuring IP forwarding in sysctl..."
    if grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        log "IP forwarding already enabled in sysctl.conf"
    else
        # Remove any existing net.ipv4.ip_forward line
        grep -v "^net.ipv4.ip_forward" /etc/sysctl.conf > /tmp/sysctl.conf.tmp || true
        mv /tmp/sysctl.conf.tmp /etc/sysctl.conf
        
        # Add the setting
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
        log "Added net.ipv4.ip_forward=1 to /etc/sysctl.conf"
    fi
    
    # Apply sysctl settings
    log "Applying sysctl settings..."
    if sysctl --system > /dev/null 2>&1; then
        log "Sysctl settings applied successfully"
    else
        # Fallback to direct sysctl command
        sysctl -p /etc/sysctl.conf > /dev/null 2>&1 || true
        warn "Used fallback method to apply sysctl settings"
    fi
    
    # Verify IP forwarding is enabled
    if [ "$(cat /proc/sys/net/ipv4/ip_forward)" -eq 1 ]; then
        log "IP forwarding is enabled (net.ipv4.ip_forward=1)"
    else
        warn "IP forwarding is not enabled. Attempting to enable temporarily..."
        echo 1 > /proc/sys/net/ipv4/ip_forward
        if [ "$(cat /proc/sys/net/ipv4/ip_forward)" -eq 1 ]; then
            log "Temporarily enabled IP forwarding"
        else
            error "Failed to enable IP forwarding. WireGuard may not work properly."
            return 1
        fi
    fi
    
    return 0
}

configure_system
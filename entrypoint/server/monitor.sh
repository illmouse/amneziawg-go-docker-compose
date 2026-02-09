#!/bin/bash
set -eu

# Source shared libraries (this script runs as a separate process)
. /entrypoint/lib/env.sh
. /entrypoint/lib/functions.sh

# Server-specific health check
check_container_health() {
    if ! is_wg_interface_up; then
        return 1
    fi

    if ! has_valid_wg_config "$WG_DIR/$WG_IFACE.conf"; then
        return 1
    fi

    if ! is_wg_listening; then
        return 1
    fi

    if ping -c 3 -W "$MON_CHECK_TIMEOUT" "$MON_CHECK_IP" >/dev/null 2>&1; then
        debug "Server health check passed: $MON_CHECK_IP"
        return 0
    else
        error "Server health check failed: $MON_CHECK_IP"
        return 1
    fi
}

# Wait for the configuration to be created
info "Starting server monitor..."

max_wait=60
waited=0
while [ ! -f "$WG_DIR/$WG_IFACE.conf" ] && [ $waited -lt $max_wait ]; do
    sleep 2
    waited=$((waited + 2))
    debug "Waiting for $WG_DIR/$WG_IFACE.conf... ($waited seconds elapsed)"
done

if [ ! -f "$WG_DIR/$WG_IFACE.conf" ]; then
    error "Timed out waiting for WireGuard configuration"
    exit 1
fi

success "WireGuard configuration found: $WG_DIR/$WG_IFACE.conf"

# Main monitoring loop
while true; do
    if check_container_health; then
        sleep "$MON_CHECK_INTERVAL"
    else
        warn "Server is unhealthy, will retry in $MON_CHECK_INTERVAL seconds"
        sleep "$MON_CHECK_INTERVAL"
    fi
done

#!/bin/bash
set -eu

# Source shared libraries (this script runs as a separate process)
. /entrypoint/lib/env.sh
. /entrypoint/lib/functions.sh

restart_wg_iface() {
    warn "amneziawg-go appears to have crashed — attempting in-place restart..."
    pkill -f "amneziawg-go $WG_IFACE" 2>/dev/null || true
    sleep 1
    start_wg_iface "$WG_IFACE"
    ip address add dev "$WG_IFACE" "$WG_ADDRESS" 2>/dev/null || true
    if ! awg setconf "$WG_IFACE" "$WG_DIR/$WG_CONF_FILE" 2>/dev/null; then
        error "Failed to reload WireGuard config after restart"
        return 1
    fi
    ip link set up dev "$WG_IFACE" 2>/dev/null || true
    success "WireGuard interface $WG_IFACE restarted"
}

# Server-specific health check
# Returns: 0 = healthy, 1 = unhealthy, 2 = wg0 interface absent
check_container_health() {
    if ! is_wg_interface_up; then
        return 2
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

max_wait=120
waited=0
while [ ! -f "$WG_DIR/$WG_IFACE.conf" ] && [ $waited -lt $max_wait ]; do
    sleep 0.5
    waited=$((waited + 1))
    debug "Waiting for $WG_DIR/$WG_IFACE.conf... ($((waited / 2)) seconds elapsed)"
done

if [ ! -f "$WG_DIR/$WG_IFACE.conf" ]; then
    error "Timed out waiting for WireGuard configuration"
    exit 1
fi

success "WireGuard configuration found: $WG_DIR/$WG_IFACE.conf"

# Main monitoring loop
_restart_failures=0
while true; do
    health_rc=0
    check_container_health || health_rc=$?
    if [ "$health_rc" -eq 0 ]; then
        _restart_failures=0
        write_tunnel_state 1
        sleep "$MON_CHECK_INTERVAL"
    elif [ "$health_rc" -eq 2 ]; then
        # wg0 is absent — attempt in-place restart
        if restart_wg_iface; then
            _restart_failures=0
        else
            _restart_failures=$(( _restart_failures + 1 ))
            error "WireGuard restart failed (attempt ${_restart_failures}/3)"
            if [ "$_restart_failures" -ge 3 ]; then
                error "Exhausted restart attempts — forcing container restart"
                kill 1
            fi
        fi
        write_tunnel_state 0
        sleep "$MON_CHECK_INTERVAL"
    else
        _restart_failures=0
        warn "Server is unhealthy, will retry in $MON_CHECK_INTERVAL seconds"
        write_tunnel_state 0
        sleep "$MON_CHECK_INTERVAL"
    fi
done

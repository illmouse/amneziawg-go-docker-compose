#!/bin/bash
set -eu

# Source shared libraries (this script runs as a separate process)
. /entrypoint/lib/env.sh
. /entrypoint/lib/functions.sh

# In-place revival of the amneziawg-go daemon: stop (sweeps stale UAPI
# socket and leftover interface), start with PID tracking, re-apply
# address/config, verify listening. Never gives up — the monitor calls
# this forever until the tunnel is back.
revive_server_wg_iface() {
    revive_wg_iface "$WG_IFACE" reload_server_wg_conf
}

# Server-specific health check
# Returns: 0 = healthy, 1 = unhealthy, 2 = wg0 interface absent
check_container_health() {
    if ! is_wg_interface_up; then
        return 2
    fi

    # Zombie state: interface exists but daemon is dead (e.g. OOM kill)
    # or its UAPI socket is gone — treat like a crash, needs revival.
    if is_wg_daemon_dead; then
        return 2
    fi

    if ! has_valid_wg_config "$WG_DIR/$WG_IFACE.conf"; then
        return 1
    fi

    if ! is_wg_listening; then
        return 1
    fi

    debug "Server health check passed"
    return 0
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

# Main monitoring loop — continuous, indefinite self-healing.
# Any unhealthy state triggers an in-place revival attempt; the loop
# never exits and never restarts the container.
_revive_attempts=0
while true; do
    health_rc=0
    check_container_health || health_rc=$?
    if [ "$health_rc" -eq 0 ]; then
        if [ "$_revive_attempts" -gt 0 ]; then
            success "Server recovered after ${_revive_attempts} revival attempt(s)"
        fi
        _revive_attempts=0
        write_tunnel_state 1
        sleep "$MON_CHECK_INTERVAL"
    else
        case "$health_rc" in
            2)
                warn "amneziawg-go crashed or interface lost — reviving in place"
                ;;
            *)
                warn "Server is unhealthy (rc=$health_rc) — reviving in place"
                ;;
        esac
        _revive_attempts=$(( _revive_attempts + 1 ))
        if revive_server_wg_iface; then
            success "Revival succeeded after ${_revive_attempts} attempt(s)"
            _revive_attempts=0
            write_tunnel_state 1
        else
            error "Revival failed (attempt ${_revive_attempts}) — will keep retrying"
            write_tunnel_state 0
        fi
        sleep "$MON_CHECK_INTERVAL"
    fi
done
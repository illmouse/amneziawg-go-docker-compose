#!/bin/bash
set -eu

# Source shared libraries (this script runs as a separate process)
. /entrypoint/lib/env.sh
. /entrypoint/lib/functions.sh
. /entrypoint/lib/config_parser.sh

# Client-specific health check
check_tunnel_health() {
    local test_target="$1"
    local timeout="$2"

    if ! is_wg_interface_up; then
        return 1
    fi

    if ! has_valid_wg_config "$WG_DIR/$WG_IFACE.conf"; then
        return 1
    fi

    if ping -c "$MON_PING_COUNT" -W "$timeout" -I "$WG_IFACE" "$test_target" >/dev/null 2>&1; then
        debug "Tunnel health check passed: $test_target"
        return 0
    else
        error "Tunnel health check failed: $test_target"
        return 1
    fi
}

# Probe a peer by spinning up a temporary awg interface and waiting for a WireGuard handshake.
# A successful handshake proves the server is reachable, WireGuard is running, and keys are valid.
# The probe interface is always torn down on exit.
probe_peer_tunnel() {
    local peer_config="$1"
    local probe_iface="awg-probe-$$"
    local probe_conf result=1

    probe_conf=$(mktemp)

    if ! build_client_config "$peer_config" "$probe_conf"; then
        warn "Failed to build probe config for $(basename "$peer_config")"
        rm -f "$probe_conf"
        return 1
    fi

    if ! amneziawg-go "$probe_iface" >>"$WG_LOGFILE" 2>&1; then
        warn "Failed to create probe interface $probe_iface"
        rm -f "$probe_conf"
        return 1
    fi

    # Route the endpoint via physical gateway so handshake traffic bypasses the main tunnel
    local endpoint_host endpoint_ip phys_gw phys_iface route_added=false
    endpoint_host=$(conf_get_value "Endpoint" "$peer_config" | cut -d: -f1)
    endpoint_ip=$(resolve_host "$endpoint_host" 2>/dev/null) || endpoint_ip="$endpoint_host"
    phys_gw=$(ip route | awk '/default/ {print $3; exit}')
    phys_iface=$(ip route | awk '/default/ {print $5; exit}')
    if [ -n "$endpoint_ip" ] && [ -n "$phys_gw" ] && [ -n "$phys_iface" ]; then
        if ip route add "$endpoint_ip" via "$phys_gw" dev "$phys_iface" 2>/dev/null; then
            route_added=true
        fi
    fi

    local probe_ip
    probe_ip=$(conf_get_value "Address" "$peer_config")
    awg setconf "$probe_iface" "$probe_conf" 2>/dev/null || true
    [ -n "$probe_ip" ] && ip addr add "$probe_ip" dev "$probe_iface" 2>/dev/null || true
    ip link set up dev "$probe_iface" 2>/dev/null || true

    # WireGuard initiates a handshake lazily (only when it has data to send).
    # Route a link-local dummy address via the probe interface and send a single
    # ping so the kernel queues a packet, triggering immediate handshake initiation.
    ip route add 169.254.1.1/32 dev "$probe_iface" 2>/dev/null || true
    ping -c 1 -W 1 -q 169.254.1.1 >/dev/null 2>&1 || true

    # Poll for a successful handshake (proves server is live and keys match)
    local deadline
    deadline=$(( $(date +%s) + MON_CHECK_TIMEOUT ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        local hs_ts
        hs_ts=$(awg show "$probe_iface" latest-handshakes 2>/dev/null | awk '{print $2}')
        if [ -n "$hs_ts" ] && [ "$hs_ts" -gt 0 ]; then
            info "Probe handshake succeeded: $(basename "$peer_config")"
            result=0
            break
        fi
        sleep 1
    done

    # Cleanup — always runs regardless of result
    [ "$result" -ne 0 ] && debug "Probe timed out for $(basename "$peer_config"): no handshake within ${MON_CHECK_TIMEOUT}s"
    ip link del "$probe_iface" 2>/dev/null || true
    if [ "$route_added" = "true" ]; then
        ip route del "$endpoint_ip" via "$phys_gw" dev "$phys_iface" 2>/dev/null || true
    fi
    rm -f "$probe_conf"

    return $result
}

# Probe all peers in rotation order starting after current_config, wrapping around to include it.
# Returns path of first peer whose probe succeeds, or empty string if none pass.
# Cooldown state is not consulted — this is a live check.
# Result is stored in _probe_result (not stdout) to avoid capturing log messages in callers.
_probe_result=""
select_and_probe_next_peer() {
    _probe_result=""
    local current_config="$1"
    local peer_files=("$CLIENT_PEERS_DIR"/*.conf)
    local peer_count=${#peer_files[@]}

    [ "$peer_count" -eq 0 ] && return 1

    IFS=$'\n' sorted_files=($(sort <<<"${peer_files[*]}"))
    unset IFS

    local current_index=-1
    for i in "${!sorted_files[@]}"; do
        if [ "${sorted_files[$i]}" = "$current_config" ]; then
            current_index=$i
            break
        fi
    done
    [ "$current_index" -eq -1 ] && current_index=0

    local i idx candidate
    for (( i=1; i<=peer_count; i++ )); do
        idx=$(( (current_index + i) % peer_count ))
        candidate="${sorted_files[$idx]}"
        info "Probing peer: $(basename "$candidate")"
        if probe_peer_tunnel "$candidate"; then
            _probe_result="$candidate"
            return 0
        fi
        warn "Probe failed: $(basename "$candidate")"
    done

    return 1
}

# Find current peer config by matching interface IP and active endpoint
find_current_peer_config() {
    local current_ip
    current_ip=$(get_iface_ip "$WG_IFACE")

    if [ -z "$current_ip" ]; then
        echo ""
        return
    fi

    # Get the active peer endpoint from the running WireGuard interface
    local current_endpoint
    current_endpoint=$(awg show "$WG_IFACE" endpoints 2>/dev/null | head -1 | awk '{print $2}')

    local peer_files=("$CLIENT_PEERS_DIR"/*.conf)

    # If we have endpoint info, match by both IP and endpoint for precision
    if [ -n "$current_endpoint" ]; then
        for peer_file in "${peer_files[@]}"; do
            if [ -f "$peer_file" ]; then
                local peer_ip peer_endpoint
                peer_ip=$(conf_get_value "Address" "$peer_file" | cut -d/ -f1)
                peer_endpoint=$(conf_get_value "Endpoint" "$peer_file")
                # Resolve config endpoint host to IP for comparison with awg show output
                local peer_endpoint_resolved=""
                if [ -n "$peer_endpoint" ]; then
                    local peer_ep_host peer_ep_port peer_ep_ip
                    peer_ep_host=$(echo "$peer_endpoint" | cut -d: -f1)
                    peer_ep_port=$(echo "$peer_endpoint" | cut -d: -f2)
                    peer_ep_ip=$(resolve_host "$peer_ep_host" 2>/dev/null) || peer_ep_ip="$peer_ep_host"
                    peer_endpoint_resolved="${peer_ep_ip}:${peer_ep_port}"
                fi
                if [ -n "$peer_ip" ] && [ "$peer_ip" = "$current_ip" ] \
                    && [ -n "$peer_endpoint_resolved" ] && [ "$peer_endpoint_resolved" = "$current_endpoint" ]; then
                    debug "Found current peer config: $(basename "$peer_file") (IP + endpoint match)" >&2
                    echo "$peer_file"
                    return 0
                fi
            fi
        done
    fi

    # Fallback: match by IP only
    for peer_file in "${peer_files[@]}"; do
        if [ -f "$peer_file" ]; then
            local peer_ip
            peer_ip=$(conf_get_value "Address" "$peer_file" | cut -d/ -f1)
            if [ -n "$peer_ip" ] && [ "$peer_ip" = "$current_ip" ]; then
                debug "Found current peer config: $(basename "$peer_file") (IP-only match)" >&2
                echo "$peer_file"
                return 0
            fi
        fi
    done

    warn "No peer configuration found matching IP $current_ip endpoint ${current_endpoint:-unknown}"
    echo ""
}

# Switch to a new peer config
switch_to_peer_config() {
    local new_config="$1"
    local current_config="$2"

    if [ -z "$new_config" ] || [ ! -f "$new_config" ]; then
        error "Cannot switch to invalid peer config: $new_config"
        return 1
    fi

    info "Switching from $(basename "$current_config") to $(basename "$new_config")"

    local new_ip
    new_ip=$(conf_get_value "Address" "$new_config")

    # Rebuild config using the shared builder (eliminates duplication)
    if build_client_config "$new_config" "$WG_DIR/$WG_IFACE.conf"; then
        # Ensure the new endpoint has a route via the physical gateway
        local new_endpoint_host new_endpoint_ip
        new_endpoint_host=$(conf_get_value "Endpoint" "$new_config" | cut -d: -f1)
        if [ -n "$new_endpoint_host" ]; then
            new_endpoint_ip=$(resolve_host "$new_endpoint_host") || true
            if [ -n "$new_endpoint_ip" ]; then
                local phys_gw phys_iface
                phys_gw=$(ip route | awk '/default/ {print $3; exit}')
                phys_iface=$(ip route | awk '/default/ {print $5; exit}')
                if [ -n "$phys_gw" ] && [ -n "$phys_iface" ]; then
                    debug "Adding endpoint route: $new_endpoint_ip via $phys_gw dev $phys_iface (host: $new_endpoint_host)"
                    ip route add "$new_endpoint_ip" via "$phys_gw" dev "$phys_iface" 2>/dev/null || true
                fi
            fi
        fi

        # Apply the rebuilt configuration
        if awg setconf "$WG_IFACE" "$WG_DIR/$WG_IFACE.conf" 2>/dev/null; then
            success "Successfully applied WireGuard configuration"

            if [ -n "$new_ip" ]; then
                # Remove current IP only after awg setconf succeeds
                # (prevents losing the address if setconf fails)
                if ip addr show "$WG_IFACE" | grep -q "inet "; then
                    local current_ip
                    current_ip=$(ip addr show "$WG_IFACE" | grep "inet " | head -1 | awk '{print $2}')
                    if [ -n "$current_ip" ]; then
                        debug "Removing current IP $current_ip from $WG_IFACE"
                        ip addr del "$current_ip" dev "$WG_IFACE" 2>/dev/null || warn "Failed to remove IP $current_ip"
                    fi
                fi

                debug "Adding new IP $new_ip to $WG_IFACE"
                if ip addr add "$new_ip" dev "$WG_IFACE" 2>/dev/null; then
                    success "Successfully added IP $new_ip to $WG_IFACE"

                    debug "Updating routing table for $WG_IFACE"
                    ip route replace default dev "$WG_IFACE" table 200 2>/dev/null || warn "Failed to update route table 200 for $WG_IFACE"

                    # Update source-based routing rule: remove old WG IP rule, add new one
                    if [ -n "${current_ip:-}" ]; then
                        ip rule del from "${current_ip%/*}" table 200 2>/dev/null || true
                    fi
                    ip rule add from "${new_ip%/*}" table 200 priority 100

                    # Reload 3proxy with the new WG IP as its outgoing source address
                    if [ "$PROXY_SOCKS5_ENABLED" = "true" ] || [ "$PROXY_HTTP_ENABLED" = "true" ]; then
                        proxy_update_external "${new_ip%/*}"
                    fi
                else
                    error "Failed to add IP $new_ip to $WG_IFACE"
                    return 1
                fi
            fi

            success "Successfully switched to $(basename "$new_config")"
            return 0
        else
            error "Failed to apply configuration: $new_config"
            return 1
        fi
    else
        error "Failed to build configuration from: $new_config"
        return 1
    fi
}

# ==========================================
# Main monitoring loop
# ==========================================
info "Starting client monitor..."

# Failover counter and last failover timestamp — persisted in tunnel state across loop iterations
failover_total=0
last_failover_ts=0

# Wait for the configuration to be created
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

while true; do
    if [ ! -d "$CLIENT_PEERS_DIR" ]; then
        warn "No peer configuration directory found in $CLIENT_PEERS_DIR"
        sleep "$MON_CHECK_INTERVAL"
        continue
    fi

    peer_files=("$CLIENT_PEERS_DIR"/*.conf)
    if [ ${#peer_files[@]} -eq 0 ] || [ ! -f "${peer_files[0]}" ]; then
        warn "No peer configuration files found in $CLIENT_PEERS_DIR"
        sleep "$MON_CHECK_INTERVAL"
        continue
    fi

    IFS=$'\n' sorted_files=($(sort <<<"${peer_files[*]}"))
    unset IFS

    # Get master peer if specified
    MASTER_PEER=${MASTER_PEER:-}
    master_peer_config=""
    if [ -n "$MASTER_PEER" ]; then
        master_peer_config="$CLIENT_PEERS_DIR/$MASTER_PEER"
        if [ ! -f "$master_peer_config" ]; then
            warn "MASTER_PEER $MASTER_PEER specified but file not found"
            master_peer_config=""
        fi
    fi

    current_peer_config=$(find_current_peer_config)

    debug "Master peer config $master_peer_config"
    debug "Current peer config: $current_peer_config"

    if check_tunnel_health "$MON_CHECK_IP" "$MON_CHECK_TIMEOUT"; then
        write_tunnel_state 1 "$(basename "${current_peer_config:-}")" "$failover_total" "$last_failover_ts"

        # Switch back to master whenever we're on a backup peer — probe first to confirm it's alive.
        if [ -n "$master_peer_config" ] && [ -n "$current_peer_config" ] && [ "$current_peer_config" != "$master_peer_config" ]; then
            info "Probing master peer $MASTER_PEER for switchback"
            if probe_peer_tunnel "$master_peer_config"; then
                info "Master peer $MASTER_PEER probe succeeded, switching back"
                if switch_to_peer_config "$master_peer_config" "$current_peer_config"; then
                    current_peer_config="$master_peer_config"
                    failover_total=$(( failover_total + 1 ))
                    last_failover_ts=$(date +%s)
                fi
            else
                warn "Master peer $MASTER_PEER probe failed, staying on backup"
            fi
        fi
        sleep "$MON_CHECK_INTERVAL"
    else
        # Tunnel is down — probe all peers before switching, to avoid blind disruption
        warn "Tunnel is down, probing available peers..."

        if [ -z "$current_peer_config" ]; then
            current_peer_config="${sorted_files[0]}"
            debug "Using initial peer config: $(basename "$current_peer_config")"
        fi

        write_tunnel_state 0 "$(basename "$current_peer_config")" "$failover_total" "$last_failover_ts"

        probe_loop_done=false
        while [ "$probe_loop_done" = "false" ]; do
            select_and_probe_next_peer "$current_peer_config" || true
            next_peer="$_probe_result"

            if [ -n "$next_peer" ]; then
                if [ "$next_peer" = "$current_peer_config" ]; then
                    # Current peer probe passed — tunnel issue was transient, stay
                    info "Current peer probe succeeded, staying on $(basename "$current_peer_config")"
                elif switch_to_peer_config "$next_peer" "$current_peer_config"; then
                    current_peer_config="$next_peer"
                    failover_total=$(( failover_total + 1 ))
                    last_failover_ts=$(date +%s)
                fi
                probe_loop_done=true
            else
                # All peer probes failed — re-check if current tunnel self-healed
                if check_tunnel_health "$MON_CHECK_IP" "$MON_CHECK_TIMEOUT"; then
                    info "Tunnel health check recovered on current peer, staying"
                    probe_loop_done=true
                else
                    warn "All peer probes failed and tunnel still down, retrying in ${MON_CHECK_INTERVAL}s..."
                    sleep "$MON_CHECK_INTERVAL"
                fi
            fi
        done

        sleep "$MON_CHECK_INTERVAL"
    fi
done

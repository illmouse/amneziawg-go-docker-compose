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

    if ping -c 3 -W "$timeout" "$test_target" >/dev/null 2>&1; then
        debug "Tunnel health check passed: $test_target"
        return 0
    else
        error "Tunnel health check failed: $test_target"
        return 1
    fi
}

# Get next peer config (circular rotation)
get_next_peer_config() {
    local current_config="$1"
    local peer_files=("$CLIENT_PEERS_DIR"/*.conf)
    local peer_count=${#peer_files[@]}

    if [ "$peer_count" -eq 0 ]; then
        echo ""
        return
    fi

    IFS=$'\n' sorted_files=($(sort <<<"${peer_files[*]}"))
    unset IFS

    local current_index=-1
    for i in "${!sorted_files[@]}"; do
        if [ "${sorted_files[$i]}" = "$current_config" ]; then
            current_index=$i
            break
        fi
    done

    if [ "$current_index" -eq -1 ] || [ "$peer_count" -eq 0 ]; then
        echo "${sorted_files[0]}"
        return
    fi

    local next_index=$(( (current_index + 1) % peer_count ))
    echo "${sorted_files[$next_index]}"
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
                if [ -n "$peer_ip" ] && [ "$peer_ip" = "$current_ip" ] \
                    && [ -n "$peer_endpoint" ] && [ "$peer_endpoint" = "$current_endpoint" ]; then
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

    # Update endpoint routing so the new peer is reachable via physical interface
    local old_endpoint_host new_endpoint_host
    old_endpoint_host=$(conf_get_value "Endpoint" "$current_config" | cut -d: -f1)
    new_endpoint_host=$(conf_get_value "Endpoint" "$new_config" | cut -d: -f1)

    if [ -n "$new_endpoint_host" ] && [ "$old_endpoint_host" != "$new_endpoint_host" ]; then
        # Get physical gateway from private network routes set by setup_client_routing
        local phys_gw phys_dev
        phys_gw=$(ip route | awk '/10\.0\.0\.0\/8 via/ {print $3; exit}')
        phys_dev=$(ip route | awk '/10\.0\.0\.0\/8 via/ {print $5; exit}')

        if [ -n "$phys_gw" ] && [ -n "$phys_dev" ]; then
            debug "Adding endpoint route: $new_endpoint_host via $phys_gw dev $phys_dev"
            ip route add "$new_endpoint_host" via "$phys_gw" dev "$phys_dev" 2>/dev/null || true

            if [ -n "$old_endpoint_host" ]; then
                debug "Removing old endpoint route: $old_endpoint_host"
                ip route del "$old_endpoint_host" via "$phys_gw" dev "$phys_dev" 2>/dev/null || true
            fi
        else
            warn "Could not determine physical gateway for endpoint routing"
        fi
    fi

    # Rebuild config using the shared builder (eliminates duplication)
    if build_client_config "$new_config" "$WG_DIR/$WG_IFACE.conf"; then
        # Remove current IP address from interface
        if ip addr show "$WG_IFACE" | grep -q "inet "; then
            local current_ip
            current_ip=$(ip addr show "$WG_IFACE" | grep "inet " | head -1 | awk '{print $2}')
            if [ -n "$current_ip" ]; then
                debug "Removing current IP $current_ip from $WG_IFACE"
                ip addr del "$current_ip" dev "$WG_IFACE" 2>/dev/null || warn "Failed to remove IP $current_ip"
            fi
        fi

        # Apply the rebuilt configuration
        if awg setconf "$WG_IFACE" "$WG_DIR/$WG_IFACE.conf" 2>/dev/null; then
            success "Successfully applied WireGuard configuration"

            if [ -n "$new_ip" ]; then
                debug "Adding new IP $new_ip to $WG_IFACE"
                if ip addr add "$new_ip" dev "$WG_IFACE" 2>/dev/null; then
                    success "Successfully added IP $new_ip to $WG_IFACE"

                    debug "Adding default route via $WG_IFACE"
                    ip route add default dev "$WG_IFACE" 2>/dev/null || warn "Failed to add default route via $WG_IFACE"
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

# Wait for the configuration to be created
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
        # Tunnel is healthy -- check if we should switch back to master peer
        debug "Tunnel is healthy, check if we should switch to master peer"
        if [ -n "$master_peer_config" ] && [ -n "$current_peer_config" ] && [ "$current_peer_config" != "$master_peer_config" ]; then
            master_endpoint=$(conf_get_value "Endpoint" "$master_peer_config")
            if [ -n "$master_endpoint" ]; then
                master_host=$(echo "$master_endpoint" | cut -d: -f1)
                master_port=$(echo "$master_endpoint" | cut -d: -f2)
                if [ -n "$master_host" ] && [ -n "$master_port" ]; then
                    if nc -zvu "$master_host" "$master_port" >/dev/null 2>&1; then
                        success "Master peer $MASTER_PEER is reachable, switching back to it"
                        if switch_to_peer_config "$master_peer_config" "$current_peer_config"; then
                            current_peer_config="$master_peer_config"
                        fi
                    fi
                fi
            fi
        fi
        sleep "$MON_CHECK_INTERVAL"
    else
        # Tunnel is down -- attempt failover via circular rotation
        # Master peer recovery is handled in the healthy path above (via nc check)
        warn "Tunnel is down, attempting to switch to next peer configuration..."

        if [ -z "$current_peer_config" ]; then
            current_peer_config="${sorted_files[0]}"
            debug "Using initial peer config: $(basename "$current_peer_config")"
        fi

        next_peer_config=$(get_next_peer_config "$current_peer_config")

        if [ -n "$next_peer_config" ] && [ -f "$next_peer_config" ]; then
            if switch_to_peer_config "$next_peer_config" "$current_peer_config"; then
                current_peer_config="$next_peer_config"
            else
                error "Failed to switch to next peer configuration, will retry in $MON_CHECK_INTERVAL seconds"
            fi
        else
            warn "No valid next peer configuration found, will retry in $MON_CHECK_INTERVAL seconds"
        fi

        sleep "$MON_CHECK_INTERVAL"
    fi
done

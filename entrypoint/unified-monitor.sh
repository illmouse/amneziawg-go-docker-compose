#!/bin/bash
# Use set -e to exit on error, but not -u to allow undefined variables
# This prevents the script from exiting if environment variables are not set
set -e

# Source functions for colors and emojis
. /entrypoint/functions.sh

# Configuration
WG_DIR="/etc/amneziawg"
WG_IFACE="wg0"
LOG_FILE="/var/log/amneziawg/unified-monitor.log"
CHECK_INTERVAL=30
CHECK_TIMEOUT=10
EXTERNAL_CHECK_TARGET="8.8.8.8"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Function to check tunnel health (client mode)
check_tunnel_health() {
    local test_target="$1"
    local timeout="$2"
    
    # Check if WireGuard interface is up
    if ! ip link show "$WG_IFACE" >/dev/null 2>&1; then
        log "❌ WireGuard interface $WG_IFACE is down"
        return 1
    fi
    
    # Check if we have a valid configuration (use the assembled wg0.conf)
    local current_config="$WG_DIR/wg0.conf"
    if [ ! -f "$current_config" ]; then
        log "❌ No WireGuard configuration found at $current_config"
        return 1
    fi
    
    # Check if we can reach the external target with ping
    if ping -c 3 -W "$timeout" "$test_target" >/dev/null 2>&1; then
        log "✅ Tunnel health check passed: $test_target"
        return 0
    else
        log "❌ Tunnel health check failed: $test_target"
        return 1
    fi
}

# Function to reassemble a peer configuration using client-mode.sh logic
reassemble_peer_config() {
    local peer_config="$1"
    local output_config="$WG_DIR/wg0.conf"
    
    if [ -z "$peer_config" ] || [ ! -f "$peer_config" ]; then
        error "Cannot reassemble invalid peer config: $peer_config"
        return 1
    fi
    
    log "🔄 Reassembling peer configuration: $(basename "$peer_config")"
    
    # Extract parameters we need
    extract_param() {
        local param="$1"
        local value=$(grep -E "^${param}[[:space:]]*=" "$peer_config" | head -1 | sed "s/^${param}[[:space:]]*=[[:space:]]*//" | tr -d '\r\n')
        echo "$value"
    }
    
    # Extract all parameters in a loop
    params="PrivateKey Jc Jmin Jmax S1 S2 H1 H2 H3 H4 Address"
    declare -A extracted_params
    
    for param in $params; do
        value=$(extract_param "$param")
        if [ -n "$value" ]; then
            extracted_params["$param"]="$value"
        fi
    done
    
    # Create the final configuration
    cat > "$output_config" << EOF
[Interface]
PrivateKey = ${extracted_params[PrivateKey]}
ListenPort = 0
EOF
    
    # Add junk parameters if they exist
    for param in Jc Jmin Jmax S1 S2 H1 H2 H3 H4; do
        if [ -n "${extracted_params[$param]}" ]; then
            echo "$param = ${extracted_params[$param]}" >> "$output_config"
        fi
    done
    
    echo "" >> "$output_config"
    
    # Extract and add peer sections
    in_peer_section=false
    peer_buffer=""
    
    while IFS= read -r line || [ -n "$line" ]; do
        line=$(printf "%s" "$line" | tr -d '\r')
        
        if [ "$line" = "[Peer]" ]; then
            if [ "$in_peer_section" = true ] && [ -n "$peer_buffer" ]; then
                echo "$peer_buffer" >> "$output_config"
                echo "" >> "$output_config"
            fi
            peer_buffer="[Peer]"
            in_peer_section=true
        elif [ "$in_peer_section" = true ]; then
            if [ -n "$line" ] && echo "$line" | grep -qE '^\[[a-zA-Z]+\]'; then
                echo "$peer_buffer" >> "$output_config"
                echo "" >> "$output_config"
                peer_buffer=""
                in_peer_section=false
            elif [ -n "$line" ] && ! echo "$line" | grep -qE '^(Address|DNS)'; then
                peer_buffer="$peer_buffer"$'\n'"$line"
            fi
        fi
    done < "$peer_config"
    
    if [ -n "$peer_buffer" ]; then
        echo "$peer_buffer" >> "$output_config"
    fi
    
    log "✅ Successfully reassembled configuration to $output_config"
    return 0
}

# Function to get next peer config
get_next_peer_config() {
    local current_config="$1"
    local peer_files=("$WG_DIR/peers"/*.conf)
    local peer_count=${#peer_files[@]}
    
    # If no peer configs exist, return empty
    if [ "$peer_count" -eq 0 ]; then
        echo ""
        return
    fi
    
    # Sort files to ensure consistent order
    IFS=$'\n' sorted_files=($(sort <<<"${peer_files[*]}"))
    unset IFS
    
    # Find current index
    local current_index=-1
    for i in "${!sorted_files[@]}"; do
        if [ "${sorted_files[$i]}" = "$current_config" ]; then
            current_index=$i
            break
        fi
    done
    
    # If current config not found or no configs, use first one
    if [ "$current_index" -eq -1 ] || [ "$peer_count" -eq 0 ]; then
        echo "${sorted_files[0]}"
        return
    fi
    
    # Calculate next index (loop back to 0 if at end)
    local next_index=$(( (current_index + 1) % peer_count ))
    echo "${sorted_files[$next_index]}"
}

# Function to switch to a new peer config (client mode)
switch_to_peer_config() {
    local new_config="$1"
    local current_config="$2"
    
    if [ -z "$new_config" ] || [ ! -f "$new_config" ]; then
        error "Cannot switch to invalid peer config: $new_config"
        return 1
    fi
    
    log "🔄 Switching from $(basename "$current_config") to $(basename "$new_config")"
    
    # Reassemble the new peer config using client-mode.sh logic
    if reassemble_peer_config "$new_config"; then
        # Apply the reassembled configuration
        if awg setconf "$WG_IFACE" "$WG_DIR/wg0.conf" >>"$LOG_FILE" 2>&1; then
            log "✅ Successfully switched to $(basename "$new_config")"
            return 0
        else
            log "❌ Failed to apply reassembled configuration: $new_config"
            return 1
        fi
    else
        log "❌ Failed to reassemble configuration: $new_config"
        return 1
    fi
}

# Function to check container health (server mode)
check_container_health() {
    # Check if WireGuard interface is up
    if ! ip link show "$WG_IFACE" >/dev/null 2>&1; then
        log "❌ WireGuard interface $WG_IFACE is down"
        return 1
    fi
    
    # Check if we have a valid configuration
    local current_config="$WG_DIR/wg0.conf"
    if [ ! -f "$current_config" ]; then
        log "❌ No WireGuard configuration found at $current_config"
        return 1
    fi
    
    # Check if WireGuard is listening
    if ! awg show "$WG_IFACE" 2>/dev/null | grep -q "listening"; then
        log "❌ WireGuard is not listening on $WG_IFACE"
        return 1
    fi
    
    # Check if we can reach the external target with ping
    if ping -c 3 -W "$CHECK_TIMEOUT" "$EXTERNAL_CHECK_TARGET" >/dev/null 2>&1; then
        log "✅ Server health check passed: $EXTERNAL_CHECK_TARGET"
        return 0
    else
        log "❌ Server health check failed: $EXTERNAL_CHECK_TARGET"
        return 1
    fi
}

# Main monitoring loop
log "🚀 Starting unified monitoring system in $WG_MODE mode"

# Wait for the assembled configuration to be created
log "⏳ Waiting for assembled WireGuard configuration to be created..."
max_wait=60
waited=0
while [ ! -f "$WG_DIR/wg0.conf" ] && [ $waited -lt $max_wait ]; do
    sleep 2
    waited=$((waited + 2))
    log "⏳ Still waiting for $WG_DIR/wg0.conf... ($waited seconds elapsed)"
done

if [ ! -f "$WG_DIR/wg0.conf" ]; then
    error "Timed out waiting for assembled WireGuard configuration to be created"
    exit 1
fi

log "✅ Assembled WireGuard configuration found: $WG_DIR/wg0.conf"

# Main monitoring loop based on mode
while true; do
    if [ "$WG_MODE" = "client" ]; then
        # Client mode monitoring
        if [ ! -d "$WG_DIR/peers" ]; then
            log "⚠️ No peer configuration directory found in $WG_DIR/peers"
            sleep "$CHECK_INTERVAL"
            continue
        fi
        
        # Get all peer configs
        peer_files=("$WG_DIR/peers"/*.conf)
        if [ ${#peer_files[@]} -eq 0 ] || [ ! -f "${peer_files[0]}" ]; then
            log "⚠️ No peer configuration files found in $WG_DIR/peers"
            sleep "$CHECK_INTERVAL"
            continue
        fi
        
        # Sort files to ensure consistent order
        IFS=$'\n' sorted_files=($(sort <<<"${peer_files[*]}"))
        unset IFS
        
        # Get master peer if specified
        MASTER_PEER=${MASTER_PEER:-}
        master_peer_config=""
        if [ -n "$MASTER_PEER" ]; then
            master_peer_config="$WG_DIR/peers/$MASTER_PEER"
            if [ ! -f "$master_peer_config" ]; then
                log "⚠️ MASTER_PEER $MASTER_PEER specified but file not found"
                master_peer_config=""
            fi
        fi
        
        # Check tunnel health
        if check_tunnel_health "$EXTERNAL_CHECK_TARGET" "$CHECK_TIMEOUT"; then
            # Tunnel is healthy, check if we should switch to master peer
            if [ -n "$master_peer_config" ] && [ -n "$current_peer_config" ] && [ "$current_peer_config" != "$master_peer_config" ]; then
                # Check if master peer is reachable (using nc to check port)
                # Extract endpoint from master peer config
                master_endpoint=$(grep -E "^Endpoint[[:space:]]*=" "$master_peer_config" | head -1 | sed "s/^Endpoint[[:space:]]*=[[:space:]]*//" | tr -d '\r\n')
                if [ -n "$master_endpoint" ]; then
                    # Extract host and port from endpoint (format: host:port)
                    master_host=$(echo "$master_endpoint" | cut -d: -f1)
                    master_port=$(echo "$master_endpoint" | cut -d: -f2)
                    if [ -n "$master_host" ] && [ -n "$master_port" ]; then
                        # Check if master peer is reachable
                        if nc -zvu "$master_host" "$master_port" >/dev/null 2>&1; then
                            log "✅ Master peer $MASTER_PEER is reachable, switching back to it"
                            if switch_to_peer_config "$master_peer_config" "$current_peer_config"; then
                                current_peer_config="$master_peer_config"
                            fi
                        fi
                    fi
                fi
            fi
            # Tunnel is healthy, wait for next check
            sleep "$CHECK_INTERVAL"
        else
            # Tunnel is down, determine which peer to switch to
            log "⚠️ Tunnel is down, attempting to switch to next peer configuration..."
            
            # If we have a master peer and it's not the current one, try master first
            if [ -n "$master_peer_config" ] && [ -n "$current_peer_config" ] && [ "$current_peer_config" != "$master_peer_config" ]; then
                # Try master peer first
                if switch_to_peer_config "$master_peer_config" "$current_peer_config"; then
                    current_peer_config="$master_peer_config"
                    log "✅ Switched to master peer $MASTER_PEER"
                else
                    log "❌ Failed to switch to master peer $MASTER_PEER, trying next available peer"
                    # Get next peer config from sorted list
                    next_peer_config=$(get_next_peer_config "$current_peer_config")
                    if [ -n "$next_peer_config" ] && [ -f "$next_peer_config" ]; then
                        if switch_to_peer_config "$next_peer_config" "$current_peer_config"; then
                            current_peer_config="$next_peer_config"
                        else
                            log "❌ Failed to switch to next peer configuration, will retry in $CHECK_INTERVAL seconds"
                        fi
                    else
                        log "❌ No valid next peer configuration found, will retry in $CHECK_INTERVAL seconds"
                    fi
                fi
            else
                # No master peer or already on master peer, use normal circular switching
                if [ -z "$current_peer_config" ]; then
                    # Initialize with first peer if not set
                    current_peer_config="${sorted_files[0]}"
                    log "🔌 Using initial peer config: $(basename "$current_peer_config")"
                fi
                
                # Get next peer config
                next_peer_config=$(get_next_peer_config "$current_peer_config")
                
                # Switch to next config
                if [ -n "$next_peer_config" ] && [ -f "$next_peer_config" ]; then
                    # Switch to next config using the reassemble logic
                    if switch_to_peer_config "$next_peer_config" "$current_peer_config"; then
                        current_peer_config="$next_peer_config"
                    else
                        log "❌ Failed to switch to next peer configuration, will retry in $CHECK_INTERVAL seconds"
                    fi
                else
                    log "❌ No valid next peer configuration found, will retry in $CHECK_INTERVAL seconds"
                fi
            fi
            
            # Wait a bit before next check after a switch
            sleep "$CHECK_INTERVAL"
        fi
        
    elif [ "$WG_MODE" = "server" ]; then
        # Server mode monitoring
        if check_container_health; then
            # Server is healthy, wait for next check
            sleep "$CHECK_INTERVAL"
        else
            # Server is unhealthy, log and wait
            log "⚠️ Server is unhealthy, will retry in $CHECK_INTERVAL seconds"
            sleep "$CHECK_INTERVAL"
        fi
        
    else
        log "❌ Unknown WG_MODE: $WG_MODE. Expected 'server' or 'client'"
        sleep "$CHECK_INTERVAL"
    fi
done

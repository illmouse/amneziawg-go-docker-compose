#!/bin/bash
set -eu

# Source functions for colors and emojis
. /entrypoint/functions.sh

# Configuration
WG_DIR="/etc/amneziawg"
PEERS_DIR="$WG_DIR/peers"
WG_IFACE="wg0"
CHECK_INTERVAL=30
CHECK_TIMEOUT=10
EXTERNAL_CHECK_TARGET="8.8.8.8"
LOG_FILE="/var/log/amneziawg/tunnel-monitor.log"
# Use the actual WireGuard configuration file created by client-mode.sh
WG_CONF_FILE="wg0.conf"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Function to log with timestamp
log() {
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*" | tee -a "$LOG_FILE"
}

# Function to get current peer config index
get_current_peer_index() {
    local current_config="$1"
    local peer_files=("$PEERS_DIR"/*.conf)
    local i=0
    for peer_file in "${peer_files[@]}"; do
        if [ -f "$peer_file" ] && [ "$(basename "$peer_file")" = "$(basename "$current_config")" ]; then
            echo "$i"
            return
        fi
        i=$((i + 1))
    done
    echo "-1"
}

# Function to get next peer config
get_next_peer_config() {
    local current_config="$1"
    local peer_files=("$PEERS_DIR"/*.conf)
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

# Function to reassemble a peer configuration using client-mode.sh logic
reassemble_peer_config() {
    local peer_config="$1"
    local output_config="$WG_DIR/$WG_CONF_FILE"
    
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

# Function to switch to a new peer config
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
        if awg setconf "$WG_IFACE" "$WG_DIR/$WG_CONF_FILE" >>"$LOG_FILE" 2>&1; then
            log "✅ Successfully switched to $(basename "$new_config")"
            current_peer_config="$new_config"
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

# Function to check tunnel health
check_tunnel_health() {
    local test_target="$1"
    local timeout="$2"
    
    # Check if WireGuard interface is up
    if ! ip link show "$WG_IFACE" >/dev/null 2>&1; then
        log "❌ WireGuard interface $WG_IFACE is down"
        return 1
    fi
    
    # Check if we have a valid configuration (use the assembled wg0.conf)
    local current_config="$WG_DIR/$WG_CONF_FILE"
    if [ ! -f "$current_config" ]; then
        log "❌ No WireGuard configuration found at $current_config"
        return 1
    fi
    
    # Check if we can reach the external target with ping
    # Use ping with timeout and count parameters
    if ping -c 3 -W "$timeout" "$test_target" >/dev/null 2>&1; then
        log "✅ Tunnel health check passed: $test_target"
        return 0
    else
        log "❌ Tunnel health check failed: $test_target"
        return 1
    fi
}

# Main monitoring loop
log "🚀 Starting tunnel health monitor with interval $CHECK_INTERVAL seconds"
log "🏓 Checking connectivity to: $EXTERNAL_CHECK_TARGET"

# Get initial peer config
peer_files=("$PEERS_DIR"/*.conf)
if [ ${#peer_files[@]} -eq 0 ] || [ ! -f "${peer_files[0]}" ]; then
    log "⚠️ No peer configuration files found in $PEERS_DIR"
    log "⚠️ Waiting for peer configurations to be generated..."
    sleep 10
fi

# Get the first available peer config
current_peer_config=""
peer_files=("$PEERS_DIR"/*.conf)
if [ ${#peer_files[@]} -gt 0 ] && [ -f "${peer_files[0]}" ]; then
    current_peer_config="${peer_files[0]}"
    log "🔌 Using initial peer config: $(basename "$current_peer_config")"
fi

# Wait for the assembled configuration to be created
log "⏳ Waiting for assembled WireGuard configuration to be created..."
max_wait=60
waited=0
while [ ! -f "$WG_DIR/$WG_CONF_FILE" ] && [ $waited -lt $max_wait ]; do
    sleep 2
    waited=$((waited + 2))
    log "⏳ Still waiting for $WG_DIR/$WG_CONF_FILE... ($waited seconds elapsed)"
done

if [ ! -f "$WG_DIR/$WG_CONF_FILE" ]; then
    error "Timed out waiting for assembled WireGuard configuration to be created"
    exit 1
fi

log "✅ Assembled WireGuard configuration found: $WG_DIR/$WG_CONF_FILE"

# Main monitoring loop
while true; do
    # Check if we have a valid peer config
    if [ -z "$current_peer_config" ] || [ ! -f "$current_peer_config" ]; then
        log "⚠️ No valid peer configuration available, waiting for one to be generated..."
        sleep "$CHECK_INTERVAL"
        continue
    fi
    
    # Check tunnel health
    if check_tunnel_health "$EXTERNAL_CHECK_TARGET" "$CHECK_TIMEOUT"; then
        # Tunnel is healthy, wait for next check
        sleep "$CHECK_INTERVAL"
    else
        # Tunnel is down, switch to next config
        log "⚠️ Tunnel is down, attempting to switch to next peer configuration..."
        
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
        
        # Wait a bit before next check after a switch
        sleep "$CHECK_INTERVAL"
    fi
done
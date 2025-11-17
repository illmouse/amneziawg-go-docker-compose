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
EXTERNAL_CHECK_URL="https://8.8.8.8"
LOG_FILE="/var/log/amneziawg/tunnel-monitor.log"

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

# Function to switch to a new peer config
switch_to_peer_config() {
    local new_config="$1"
    local current_config="$2"
    
    if [ -z "$new_config" ] || [ ! -f "$new_config" ]; then
        error "Cannot switch to invalid peer config: $new_config"
        return 1
    fi
    
    log "🔄 Switching from $(basename "$current_config") to $(basename "$new_config")"
    
    # Load the new configuration
    if awg setconf "$WG_IFACE" "$new_config" >>"$LOG_FILE" 2>&1; then
        log "✅ Successfully switched to $(basename "$new_config")"
        
        # Verify the interface is up and has an IP
        if ip link show "$WG_IFACE" >/dev/null 2>&1; then
            log "✅ WireGuard interface $WG_IFACE is up"
        else
            log "❌ WireGuard interface $WG_IFACE is down after switch"
            return 1
        fi
        
        # Check if we have a valid endpoint
        local endpoint=$(grep -E '^Endpoint' "$new_config" | head -1 | awk -F'=' '{print $2}' | awk -F':' '{print $1}' | tr -d ' ')
        if [ -n "$endpoint" ]; then
            log "🌐 New endpoint: $endpoint"
        fi
        
        return 0
    else
        error "Failed to load configuration: $new_config"
        return 1
    fi
}

# Function to check tunnel health
check_tunnel_health() {
    local test_url="$1"
    local timeout="$2"
    
    # Check if WireGuard interface is up
    if ! ip link show "$WG_IFACE" >/dev/null 2>&1; then
        log "❌ WireGuard interface $WG_IFACE is down"
        return 1
    fi
    
    # Check if we have a valid configuration
    local current_config="$WG_DIR/$WG_IFACE.conf"
    if [ ! -f "$current_config" ]; then
        log "❌ No WireGuard configuration found at $current_config"
        return 1
    fi
    
    # Check if we can reach the external URL
    if curl --connect-timeout "$timeout" --max-time "$timeout" --silent --fail "$test_url" >/dev/null 2>&1; then
        log "✅ Tunnel health check passed: $test_url"
        return 0
    else
        log "❌ Tunnel health check failed: $test_url"
        return 1
    fi
}

# Main monitoring loop
log "🚀 Starting tunnel health monitor with interval $CHECK_INTERVAL seconds"
log "🌐 Checking connectivity to: $EXTERNAL_CHECK_URL"

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

# Main monitoring loop
while true; do
    # Check if we have a valid peer config
    if [ -z "$current_peer_config" ] || [ ! -f "$current_peer_config" ]; then
        log "⚠️ No valid peer configuration available, waiting for one to be generated..."
        sleep "$CHECK_INTERVAL"
        continue
    fi
    
    # Check tunnel health
    if check_tunnel_health "$EXTERNAL_CHECK_URL" "$CHECK_TIMEOUT"; then
        # Tunnel is healthy, wait for next check
        sleep "$CHECK_INTERVAL"
    else
        # Tunnel is down, switch to next config
        log "⚠️ Tunnel is down, attempting to switch to next peer configuration..."
        
        # Get next peer config
        next_peer_config=$(get_next_peer_config "$current_peer_config")
        
        # Switch to next config
        if switch_to_peer_config "$next_peer_config" "$current_peer_config"; then
            # Update current config
            current_peer_config="$next_peer_config"
        else
            log "❌ Failed to switch to next peer configuration, will retry in $CHECK_INTERVAL seconds"
        fi
        
        # Wait a bit before next check after a switch
        sleep "$CHECK_INTERVAL"
    fi
done
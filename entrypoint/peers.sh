#!/bin/sh
set -eu

. /entrypoint/functions.sh

manage_peers() {
    local current_peer_count=$(jq '.peers | keys | length' "$CONFIG_DB")
    local desired_peer_count=$WG_PEER_COUNT
    
    log "Managing peers: current=$current_peer_count, desired=$desired_peer_count"
    
    # Add new peers if needed
    if [ "$desired_peer_count" -gt "$current_peer_count" ]; then
        for i in $(seq $((current_peer_count + 1)) "$desired_peer_count"); do
            add_peer "$i"
        done
    fi
    # Note: We don't remove peers if count decreases (as requested)
}

add_peer() {
    local peer_id="$1"
    local peer_ip=$(get_peer_ip "$peer_id")
    local peer_name="peer$peer_id"
    
    log "Adding new peer: $peer_name ($peer_ip)"
    
    # Generate keys
    local peer_priv_key=$(gen_key)
    local peer_pub_key=$(pub_from_priv "$peer_priv_key")
    local psk=$(gen_psk)
    
    # Save keys to files
    echo "$peer_priv_key" > "$KEYS_DIR/${peer_name}_privatekey"
    echo "$peer_pub_key" > "$KEYS_DIR/${peer_name}_publickey"
    echo "$psk" > "$KEYS_DIR/${peer_name}_presharedkey"
    
    # Add to database
    local peer_json=$(jq -n \
        --arg name "$peer_name" \
        --arg ip "$peer_ip" \
        --arg priv_key "$peer_priv_key" \
        --arg pub_key "$peer_pub_key" \
        --arg psk "$psk" \
        '{
            name: $name,
            ip: $ip,
            private_key: $priv_key,
            public_key: $pub_key,
            preshared_key: $psk,
            created: now | todate
        }')
    
    set_db_value ".peers.\"$peer_name\"" "$peer_json"
    log "Peer $peer_name added to database"
}

manage_peers
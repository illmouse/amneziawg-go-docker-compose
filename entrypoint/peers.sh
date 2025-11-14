#!/bin/sh

. /entrypoint/functions.sh

log "DEBUG: peers.sh - Starting execution"

current_peer_count=$(jq '.peers | keys | length' "$CONFIG_DB" 2>/dev/null || echo "0")
desired_peer_count=${WG_PEER_COUNT:-1}

log "Managing peers: current=$current_peer_count, desired=$desired_peer_count"

# Add new peers if needed
if [ "$desired_peer_count" -gt "$current_peer_count" ]; then
    log "Adding $((desired_peer_count - current_peer_count)) new peer(s)..."
    for i in $(seq $((current_peer_count + 1)) "$desired_peer_count"); do
        peer_ip=$(get_peer_ip "$i")
        peer_name="peer$i"
        
        log "Adding new peer: $peer_name ($peer_ip)"
        
        # Check if peer already exists
        existing_peer=$(get_db_value ".peers.\"$peer_name\"")
        if [ -n "$existing_peer" ] && [ "$existing_peer" != "null" ]; then
            log "Peer $peer_name already exists, skipping"
            continue
        fi
        
        # Generate keys
        peer_priv_key=$(gen_key)
        peer_pub_key=$(pub_from_priv "$peer_priv_key")
        psk=$(gen_psk)
        
        # Add to database
        peer_json=$(jq -n \
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
        
        if set_db_value ".peers.\"$peer_name\"" "$peer_json"; then
            log "Peer $peer_name added to database successfully"
        else
            error "Failed to add peer $peer_name to database"
        fi
    done
else
    log "No new peers to add (current: $current_peer_count, desired: $desired_peer_count)"
fi

log "DEBUG: peers.sh - Completed successfully"
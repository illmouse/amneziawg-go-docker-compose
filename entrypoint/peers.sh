#!/bin/bash

. /entrypoint/functions.sh

info "${PEER_EMOJI} Managing peers..."

# Helper: Archive a peer configuration file
archive_peer_conf() {
    local peer_name="$1"
    local suffix="$2"
    local archive_date
    archive_date=$(date -u +'%Y%m%d')
    local peer_conf_file="$PEERS_DIR/${peer_name}.conf"
    if [ -f "$peer_conf_file" ]; then
        local archive_file="$PEERS_DIR/${peer_name}.conf.${suffix}.${archive_date}"
        if [ -f "$archive_file" ]; then
            archive_file="$archive_file.$(date -u +'%H%M%S')"
        fi
        mv "$peer_conf_file" "$archive_file"
        info "Archived peer configuration: $peer_conf_file → $archive_file"
    fi
}

# Helper: Add peer to DB and generate keys
add_peer_to_db() {
    local peer_name="$1"
    local peer_ip="$2"
    local peer_priv_key peer_pub_key psk

    peer_priv_key=$(gen_key)
    peer_pub_key=$(pub_from_priv "$peer_priv_key")
    psk=$(gen_psk)

    local peer_json
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
        success "Peer $peer_name added to database"
        update_peer_conf "$peer_name"
    else
        error "Failed to add peer $peer_name to database"
    fi
}

# Helper: Generate peer configuration file from DB
update_peer_conf() {
    local peer_name="$1"
    local peer_data
    peer_data=$(jq -r --arg peer "$peer_name" '.peers[$peer]' "$CONFIG_DB")

    if [ -z "$peer_data" ] || [ "$peer_data" = "null" ]; then
        warn "No data for peer $peer_name"
        return
    fi

    local peer_ip peer_private_key peer_preshared_key server_pub_key server_endpoint server_port
    peer_ip=$(echo "$peer_data" | jq -r '.ip')
    peer_private_key=$(echo "$peer_data" | jq -r '.private_key')
    peer_preshared_key=$(echo "$peer_data" | jq -r '.preshared_key')
    server_pub_key=$(get_db_value '.server.keys.public_key')
    server_endpoint=$(get_db_value '.server.endpoint')
    server_port=$(get_db_value '.server.port')

    cat > "$PEERS_DIR/${peer_name}.conf" << EOF
[Interface]
PrivateKey = $peer_private_key
Address = $peer_ip
DNS = 8.8.8.8

[Peer]
PublicKey = $server_pub_key
PresharedKey = $peer_preshared_key
Endpoint = $server_endpoint:$server_port
AllowedIPs = 0.0.0.0/0
EOF

    info "Updated configuration for peer: $peer_name"
}

# MAIN LOGIC

current_peer_count=$(jq '.peers | keys | length' "$CONFIG_DB" 2>/dev/null || echo "0")
desired_peer_count=${WG_PEER_COUNT:-1}
info "Current peers in DB: $current_peer_count, desired: $desired_peer_count"

# Backup DB
cp "$CONFIG_DB" "$CONFIG_DB.backup" 2>/dev/null || true

# Remove excess peers
if [ "$current_peer_count" -gt "$desired_peer_count" ]; then
    info "Removing $((current_peer_count - desired_peer_count)) excess peer(s)..."
    
    # Get all peers sorted numerically
    all_peers=$(jq -r '.peers | keys | .[]' "$CONFIG_DB" 2>/dev/null)
    sorted_peers=$(echo "$all_peers" | awk '{gsub("peer",""); printf "%d %s\n",$0,$0}' | sort -n | awk '{print "peer"$2}')
    
    # Split into peers to keep and remove
    peers_to_keep=$(echo "$sorted_peers" | head -n "$desired_peer_count")
    peers_to_remove=$(echo "$sorted_peers" | tail -n +"$((desired_peer_count + 1))")
    
    # Remove from DB and archive configs
    for peer in $peers_to_remove; do
        jq "del(.peers[\"$peer\"])" "$CONFIG_DB" > "$CONFIG_DB.tmp" && mv "$CONFIG_DB.tmp" "$CONFIG_DB"
        archive_peer_conf "$peer" "removed"
    done
    success "Removed excess peers"
fi

# Recompute current count
current_peer_count=$(jq '.peers | keys | length' "$CONFIG_DB" 2>/dev/null || echo "0")
peers_needed=$((desired_peer_count - current_peer_count))

# Add missing peers
if [ "$peers_needed" -gt 0 ]; then
    info "Adding $peers_needed new peer(s)..."
    existing_numbers=$(jq -r '.peers | keys | map(.[4:] | tonumber) | sort | .[]' "$CONFIG_DB" 2>/dev/null || echo "")
    peers_added=0

    # Fill gaps first
    for i in $(seq 1 "$desired_peer_count"); do
        if [ "$peers_added" -ge "$peers_needed" ]; then break; fi
        peer_exists=$(jq -r --arg peer "peer$i" '.peers | has($peer)' "$CONFIG_DB")
        if [ "$peer_exists" = "false" ]; then
            peer_ip=$(get_peer_ip "$i")
            add_peer_to_db "peer$i" "$peer_ip"
            peers_added=$((peers_added + 1))
        fi
    done

    # Add sequential peers if still needed
    if [ "$peers_added" -lt "$peers_needed" ]; then
        highest_existing=${existing_numbers##*$'\n'}
        for i in $(seq 1 $((peers_needed - peers_added))); do
            peer_num=$((highest_existing + i))
            peer_ip=$(get_peer_ip "$peer_num")
            add_peer_to_db "peer$peer_num" "$peer_ip"
        done
    fi
fi

# Update all peer configs unconditionally
info "Updating all peer configuration files from database..."
all_peers_sorted=$(jq -r '.peers | keys | .[]' "$CONFIG_DB" 2>/dev/null)
for peer in $all_peers_sorted; do
    update_peer_conf "$peer"
done

final_count=$(jq '.peers | keys | length' "$CONFIG_DB")
active_peers=$(jq -r '.peers | keys | sort | join(", ")' "$CONFIG_DB" 2>/dev/null || echo "none")
success "${PEER_EMOJI} Peer management completed: $final_count peer(s) active"
info "Active peers: $active_peers"

#!/bin/bash

. /entrypoint/functions.sh

debug "${PEER_EMOJI} Managing peers..."

# Helper: Archive a peer configuration file
archive_peer_conf() {
    local peer_name="$1"
    local suffix="$2"
    local archive_date
    archive_date=$(date -u +'%Y%m%d')
    local peer_conf_file="$SERVER_PEERS_DIR/${peer_name}.conf"
    if [ -f "$peer_conf_file" ]; then
        local archive_file="$SERVER_PEERS_DIR/${peer_name}.conf.${suffix}.${archive_date}"
        if [ -f "$archive_file" ]; then
            archive_file="$archive_file.$(date -u +'%H%M%S')"
        fi
        mv "$peer_conf_file" "$archive_file"
        debug "Archived peer configuration: $peer_conf_file → $archive_file"
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
        # Do NOT generate peer config here, generate_configs.sh will handle it
    else
        error "Failed to add peer $peer_name to database"
    fi
}

# MAIN LOGIC

current_peer_count=$(jq '.peers | keys | length' "$CONFIG_DB" 2>/dev/null || echo "0")
desired_peer_count=${WG_PEER_COUNT:-1}
debug "Current peers in DB: $current_peer_count, desired: $desired_peer_count"

# Backup DB
cp "$CONFIG_DB" "$CONFIG_DB.backup" 2>/dev/null || true

# Remove excess peers
if [ "$current_peer_count" -gt "$desired_peer_count" ]; then
    debug "Removing $((current_peer_count - desired_peer_count)) excess peer(s)..."
    
    # Compute arrays safely
    peers_all=($(jq -r '.peers | keys | sort_by(.[4:] | tonumber) | .[]' "$CONFIG_DB"))
    
    peers_to_keep=("${peers_all[@]:0:desired_peer_count}")
    peers_to_remove=("${peers_all[@]:desired_peer_count}")

    for peer in "${peers_to_remove[@]}"; do
        jq "del(.peers[\"$peer\"])" "$CONFIG_DB" > "$CONFIG_DB.tmp" && mv "$CONFIG_DB.tmp" "$CONFIG_DB"
        archive_peer_conf "$peer" "removed"
    done
    success "Removed excess peers"
fi

# Add missing peers
current_peer_count=$(jq '.peers | keys | length' "$CONFIG_DB" 2>/dev/null || echo "0")
peers_needed=$((desired_peer_count - current_peer_count))

if [ "$peers_needed" -gt 0 ]; then
    debug "Adding $peers_needed new peer(s)..."
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

success "${PEER_EMOJI} Peer management completed"

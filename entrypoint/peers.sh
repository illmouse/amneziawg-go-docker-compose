#!/bin/bash

. /entrypoint/functions.sh

info "${PEER_EMOJI} Managing peers..."

# Get current and desired peer counts
current_peer_count=$(jq '.peers | keys | length' "$CONFIG_DB" 2>/dev/null || echo "0")
desired_peer_count=${WG_PEER_COUNT:-1}

info "Current peers in DB: $current_peer_count, desired: $desired_peer_count"

# Create a backup of the original database
cp "$CONFIG_DB" "$CONFIG_DB.backup" 2>/dev/null || true

# Get current date for archival
archive_date=$(date -u +'%Y%m%d')

# Remove peers beyond desired count from active configuration
if [ "$current_peer_count" -gt "$desired_peer_count" ]; then
    info "Removing ${CYAN}$((current_peer_count - desired_peer_count))${NC} peer(s) from active configuration..."
    
    # Get the list of peers to keep (first N peers sorted numerically)
    peers_to_keep=$(jq -r '.peers | keys | sort_by(.[4:] | tonumber) | .[0:'"$desired_peer_count"'] | .[]' "$CONFIG_DB")
    
    # Get the list of peers that will be removed
    all_peers=$(jq -r '.peers | keys | sort_by(.[4:] | tonumber) | .[]' "$CONFIG_DB")
    peers_to_remove=$(echo "$all_peers" | tail -n +$((desired_peer_count + 1)))
    
    if [ -n "$peers_to_keep" ]; then
        # Create a new peers object with only the kept peers
        temp_peers='{}'
        for peer in $peers_to_keep; do
            peer_data=$(jq -r --arg peer "$peer" '.peers[$peer]' "$CONFIG_DB")
            temp_peers=$(echo "$temp_peers" | jq --arg peer "$peer" --argjson data "$peer_data" '.[$peer] = $data')
        done
        
        # Update the database with only the kept peers
        if jq --argjson new_peers "$temp_peers" '.peers = $new_peers' "$CONFIG_DB" > "$CONFIG_DB.tmp" 2>/dev/null; then
            if [ -s "$CONFIG_DB.tmp" ] && jq empty "$CONFIG_DB.tmp" 2>/dev/null; then
                mv "$CONFIG_DB.tmp" "$CONFIG_DB"
                success "Removed peers beyond count $desired_peer_count from active configuration"
                
                # Archive configuration files for removed peers instead of deleting
                for peer in $peers_to_remove; do
                    peer_conf_file="$PEERS_DIR/${peer}.conf"
                    if [ -f "$peer_conf_file" ]; then
                        archive_file="$PEERS_DIR/${peer}.conf.removed.${archive_date}"
                        # If archive already exists for today, add timestamp
                        if [ -f "$archive_file" ]; then
                            archive_file="$PEERS_DIR/${peer}.conf.removed.${archive_date}.$(date -u +'%H%M%S')"
                        fi
                        mv "$peer_conf_file" "$archive_file"
                        info "Archived peer configuration: $peer_conf_file → $archive_file"
                    fi
                done
                
                # Verify the removal worked
                new_count=$(jq '.peers | keys | length' "$CONFIG_DB")
                if [ "$new_count" -eq "$desired_peer_count" ]; then
                    success "Verified: Database now contains $new_count peer(s)"
                else
                    warn "Peer count mismatch: expected $desired_peer_count, got $new_count. Restoring backup."
                    mv "$CONFIG_DB.backup" "$CONFIG_DB" 2>/dev/null || true
                fi
            else
                warn "Generated invalid JSON, restoring backup"
                mv "$CONFIG_DB.backup" "$CONFIG_DB" 2>/dev/null || true
            fi
        else
            warn "Failed to update database, restoring backup"
            mv "$CONFIG_DB.backup" "$CONFIG_DB" 2>/dev/null || true
        fi
    else
        warn "No peers to keep - resetting peers object"
        if jq '.peers = {}' "$CONFIG_DB" > "$CONFIG_DB.tmp" 2>/dev/null; then
            mv "$CONFIG_DB.tmp" "$CONFIG_DB"
            # Archive all peer configuration files
            for peer_conf in "$PEERS_DIR"/*.conf; do
                if [ -f "$peer_conf" ]; then
                    peer_name=$(basename "$peer_conf" .conf)
                    archive_file="$PEERS_DIR/${peer_name}.conf.removed.${archive_date}"
                    # If archive already exists for today, add timestamp
                    if [ -f "$archive_file" ]; then
                        archive_file="$PEERS_DIR/${peer_name}.conf.removed.${archive_date}.$(date -u +'%H%M%S')"
                    fi
                    mv "$peer_conf" "$archive_file"
                    info "Archived peer configuration: $peer_conf → $archive_file"
                fi
            done
            success "Reset peers object to empty"
        else
            warn "Failed to reset peers object, restoring backup"
            mv "$CONFIG_DB.backup" "$CONFIG_DB" 2>/dev/null || true
        fi
    fi
fi

# Re-read current count after potential removal
current_peer_count=$(jq '.peers | keys | length' "$CONFIG_DB" 2>/dev/null || echo "0")

# Add new peers if needed, filling gaps first
if [ "$desired_peer_count" -gt "$current_peer_count" ]; then
    info "Adding ${GREEN}$((desired_peer_count - current_peer_count))${NC} new peer(s)..."
    
    # Get existing peer numbers
    existing_numbers=$(jq -r '.peers | keys | map(.[4:] | tonumber) | sort | .[]' "$CONFIG_DB" 2>/dev/null || echo "")
    
    peers_added=0
    peers_needed=$((desired_peer_count - current_peer_count))
    newly_added_peers=""
    
    # First pass: fill gaps in numbering from 1 to desired count
    for i in $(seq 1 "$desired_peer_count"); do
        # If we've added all needed peers, break
        if [ "$peers_added" -ge "$peers_needed" ]; then
            break
        fi
        
        # Check if peer$i exists
        peer_exists=$(jq -r --arg peer "peer$i" '.peers | has($peer)' "$CONFIG_DB")
        if [ "$peer_exists" = "false" ]; then
            peer_name="peer$i"
            peer_ip=$(get_peer_ip "$i")
            
            info "Adding missing peer: $peer_name ($peer_ip)"
            
            # Generate keys
            peer_priv_key=$(gen_key)
            peer_pub_key=$(pub_from_priv "$peer_priv_key")
            psk=$(gen_psk)
            
            # Archive existing configuration file if it exists (from previous incarnation)
            peer_conf_file="$PEERS_DIR/${peer_name}.conf"
            if [ -f "$peer_conf_file" ]; then
                archive_file="$PEERS_DIR/${peer_name}.conf.archived.${archive_date}"
                # If archive already exists for today, add timestamp
                if [ -f "$archive_file" ]; then
                    archive_file="$PEERS_DIR/${peer_name}.conf.archived.${archive_date}.$(date -u +'%H%M%S')"
                fi
                mv "$peer_conf_file" "$archive_file"
                info "Archived previous peer configuration: $peer_conf_file → $archive_file"
            fi
            
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
                success "Peer $peer_name added to database"
                peers_added=$((peers_added + 1))
                newly_added_peers="$newly_added_peers $peer_name"
            else
                error "Failed to add peer $peer_name to database"
            fi
        fi
    done
    
    # Second pass: if still need more peers, add sequential at the end
    if [ "$peers_added" -lt "$peers_needed" ]; then
        additional_needed=$((peers_needed - peers_added))
        
        # Find the highest existing peer number
        highest_existing=0
        if [ -n "$existing_numbers" ]; then
            highest_existing=$(echo "$existing_numbers" | tail -1)
        fi
        
        info "Adding ${GREEN}$additional_needed${NC} additional sequential peer(s)..."
        
        for i in $(seq 1 "$additional_needed"); do
            peer_num=$((highest_existing + i))
            peer_name="peer$peer_num"
            peer_ip=$(get_peer_ip "$peer_num")
            
            info "Adding new sequential peer: $peer_name ($peer_ip)"
            
            # Generate keys
            peer_priv_key=$(gen_key)
            peer_pub_key=$(pub_from_priv "$peer_priv_key")
            psk=$(gen_psk)
            
            # Archive existing configuration file if it exists
            peer_conf_file="$PEERS_DIR/${peer_name}.conf"
            if [ -f "$peer_conf_file" ]; then
                archive_file="$PEERS_DIR/${peer_name}.conf.archived.${archive_date}"
                # If archive already exists for today, add timestamp
                if [ -f "$archive_file" ]; then
                    archive_file="$PEERS_DIR/${peer_name}.conf.archived.${archive_date}.$(date -u +'%H%M%S')"
                fi
                mv "$peer_conf_file" "$archive_file"
                info "Archived previous peer configuration: $peer_conf_file → $archive_file"
            fi
            
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
                success "Peer $peer_name added to database"
                newly_added_peers="$newly_added_peers $peer_name"
            else
                error "Failed to add peer $peer_name to database"
            fi
        done
    fi
    
    # Log which peers were newly added
    if [ -n "$newly_added_peers" ]; then
        info "Newly added peers that will get fresh configurations: $newly_added_peers"
    fi
else
    success "No peer changes needed"
fi

# Clean up backup
rm -f "$CONFIG_DB.backup" 2>/dev/null || true

# Final count and list
final_peer_count=$(jq '.peers | keys | length' "$CONFIG_DB")
active_peers=$(jq -r '.peers | keys | sort_by(.[4:] | tonumber) | join(", ")' "$CONFIG_DB" 2>/dev/null || echo "none")

success "${PEER_EMOJI} Peer management completed: $final_peer_count peer(s) active"
info "Active peers: $active_peers"

# UNCONDITIONALLY UPDATE ALL PEER CONFIG FILES FROM DATABASE
info "Updating all peer configuration files from database..."
peers_updated=0

# Get all active peers from database
active_peers_list=$(jq -r '.peers | keys | sort_by(.[4:] | tonumber) | .[]' "$CONFIG_DB" 2>/dev/null)

if [ -n "$active_peers_list" ]; then
    for peer in $active_peers_list; do
        peer_data=$(jq -r --arg peer "$peer" '.peers[$peer]' "$CONFIG_DB")
        
        if [ -n "$peer_data" ] && [ "$peer_data" != "null" ]; then
            peer_name=$(echo "$peer_data" | jq -r '.name')
            peer_ip=$(echo "$peer_data" | jq -r '.ip')
            peer_private_key=$(echo "$peer_data" | jq -r '.private_key')
            peer_public_key=$(echo "$peer_data" | jq -r '.public_key')
            peer_preshared_key=$(echo "$peer_data" | jq -r '.preshared_key')
            
            # Generate the peer configuration file
            peer_conf_file="$PEERS_DIR/${peer_name}.conf"
            
            cat > "$peer_conf_file" << EOF
[Interface]
PrivateKey = $peer_private_key
Address = $peer_ip
DNS = 8.8.8.8

[Peer]
PublicKey = $(get_db_value '.server.public_key')
PresharedKey = $peer_preshared_key
Endpoint = $(get_db_value '.server.endpoint'):$(get_db_value '.server.port')
AllowedIPs = 0.0.0.0/0
EOF
            
            if [ -f "$peer_conf_file" ]; then
                peers_updated=$((peers_updated + 1))
                info "Updated configuration for peer: $peer_name"
            else
                warn "Failed to create configuration file for peer: $peer_name"
            fi
        else
            warn "No data found for peer: $peer"
        fi
    done
    
    success "Updated configuration files for $peers_updated peer(s)"
else
    info "No active peers found to update"
fi
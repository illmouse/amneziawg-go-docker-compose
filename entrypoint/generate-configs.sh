#!/bin/sh
set -eu

. /entrypoint/functions.sh

generate_server_config() {
    local server_priv_key=$(get_db_value '.server.keys.private_key')
    local server_jc=$(get_db_value '.server.junk.jc')
    local server_jmin=$(get_db_value '.server.junk.jmin')
    local server_jmax=$(get_db_value '.server.junk.jmax')
    local server_s1=$(get_db_value '.server.junk.s1')
    local server_s2=$(get_db_value '.server.junk.s2')
    local server_h1=$(get_db_value '.server.junk.h1')
    local server_h2=$(get_db_value '.server.junk.h2')
    local server_h3=$(get_db_value '.server.junk.h3')
    local server_h4=$(get_db_value '.server.junk.h4')
    
    TMP_CONF="$TMP_DIR/$WG_CONF_FILE"
    
    # Start server config
    cat > "$TMP_CONF" <<EOF
[Interface]
PrivateKey = $server_priv_key
ListenPort = $WG_PORT
Jc = $server_jc
Jmin = $server_jmin
Jmax = $server_jmax
S1 = $server_s1
S2 = $server_s2
H1 = $server_h1
H2 = $server_h2
H3 = $server_h3
H4 = $server_h4

EOF
    
    # Add peers
    jq -r '.peers | to_entries[] | 
        "[Peer]\n" +
        "PublicKey = " + .value.public_key + "\n" +
        "PresharedKey = " + .value.preshared_key + "\n" +
        "AllowedIPs = " + .value.ip + "\n"' "$CONFIG_DB" >> "$TMP_CONF"
    
    # Deploy config if changed
    CONF_PATH="$WG_DIR/$WG_CONF_FILE"
    if [ -f "$CONF_PATH" ] && cmp -s "$TMP_CONF" "$CONF_PATH"; then
        log "Server config unchanged."
    else
        log "Server config updated."
        cp "$TMP_CONF" "$CONF_PATH"
    fi
}

generate_peer_configs() {
    local server_pub_key=$(get_db_value '.server.keys.public_key')
    local server_endpoint=$(get_db_value '.server.endpoint')
    local server_port=$(get_db_value '.server.port')
    local server_jc=$(get_db_value '.server.junk.jc')
    local server_jmin=$(get_db_value '.server.junk.jmin')
    local server_jmax=$(get_db_value '.server.junk.jmax')
    local server_s1=$(get_db_value '.server.junk.s1')
    local server_s2=$(get_db_value '.server.junk.s2')
    local server_h1=$(get_db_value '.server.junk.h1')
    local server_h2=$(get_db_value '.server.junk.h2')
    local server_h3=$(get_db_value '.server.junk.h3')
    local server_h4=$(get_db_value '.server.junk.h4')
    
    jq -r '.peers | to_entries[] | 
        .key + " " + .value.private_key + " " + .value.ip + " " + .value.preshared_key' "$CONFIG_DB" | \
    while read -r peer_name peer_priv_key peer_ip peer_psk; do
        PEER_CONF_FILE="$PEERS_DIR/${peer_name}.conf"
        
        cat > "$PEER_CONF_FILE" <<EOF
[Interface]
PrivateKey = $peer_priv_key
Address = $peer_ip
DNS = 9.9.9.9,149.112.112.112
Jc = $server_jc
Jmin = $server_jmin
Jmax = $server_jmax
S1 = $server_s1
S2 = $server_s2
H1 = $server_h1
H2 = $server_h2
H3 = $server_h3
H4 = $server_h4

[Peer]
PublicKey = $server_pub_key
PresharedKey = $peer_psk
Endpoint = $server_endpoint:$server_port
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
        log "Peer config generated: $PEER_CONF_FILE"
    done
}

generate_server_config
generate_peer_configs

# Fix permissions
log "Changing permissions to 600 for $WG_DIR"
chmod -R 600 "$WG_DIR"
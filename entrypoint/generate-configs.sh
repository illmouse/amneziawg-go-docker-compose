#!/bin/bash

. /entrypoint/functions.sh

info "${CONFIG_EMOJI} Generating server configuration..."

server_priv_key=$(get_db_value '.server.keys.private_key')
server_jc=$(get_db_value '.server.junk.jc')
server_jmin=$(get_db_value '.server.junk.jmin')
server_jmax=$(get_db_value '.server.junk.jmax')
server_s1=$(get_db_value '.server.junk.s1')
server_s2=$(get_db_value '.server.junk.s2')
server_h1=$(get_db_value '.server.junk.h1')
server_h2=$(get_db_value '.server.junk.h2')
server_h3=$(get_db_value '.server.junk.h3')
server_h4=$(get_db_value '.server.junk.h4')

# Validate server private key exists
if [ -z "$server_priv_key" ] || [ "$server_priv_key" = "null" ]; then
    error "Server private key not found in database"
fi

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

# Add peers from database
peers_count=$(jq '.peers | keys | length' "$CONFIG_DB")
if [ "$peers_count" -gt 0 ]; then
    info "Adding $peers_count peer(s) to server config"
    jq -r '.peers | to_entries[] | 
        "[Peer]\n" +
        "PublicKey = " + .value.public_key + "\n" +
        "PresharedKey = " + .value.preshared_key + "\n" +
        "AllowedIPs = " + (.value.ip | sub("/.*"; "")) + "/32\n"' "$CONFIG_DB" >> "$TMP_CONF"
else
    warn "No peers found in database to add to server config"
fi

# Deploy config if changed
CONF_PATH="$WG_DIR/$WG_CONF_FILE"
if [ -f "$CONF_PATH" ] && cmp -s "$TMP_CONF" "$CONF_PATH"; then
    success "Server config unchanged"
else
    info "Server config updated"
    cp "$TMP_CONF" "$CONF_PATH"
    success "Server configuration file deployed: $CONF_PATH"
fi

# Generate peer configs
info "${CONFIG_EMOJI} Generating peer configurations..."

server_pub_key=$(get_db_value '.server.keys.public_key')
server_endpoint=$(get_db_value '.server.endpoint')
server_port=$(get_db_value '.server.port')

# Validate server public key exists
if [ -z "$server_pub_key" ] || [ "$server_pub_key" = "null" ]; then
    error "Server public key not found in database"
fi

if [ "$peers_count" -eq 0 ]; then
    warn "No peers found in database to generate configs for"
else
    info "Generating $peers_count peer configuration file(s)..."
    
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
        success "Peer config generated: $PEER_CONF_FILE"
    done
fi

success "${CONFIG_EMOJI} Configuration generation completed"
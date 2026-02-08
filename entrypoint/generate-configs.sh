#!/bin/bash

. /entrypoint/functions.sh

info "${CONFIG_EMOJI} Generating server configuration..."

# Get server junk values
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

[ -z "$server_priv_key" ] && error "Server private key not found in database"

TMP_CONF="$TMP_DIR/$WG_CONF_FILE"

# Make sure TMP_DIR exists
mkdir -p "$TMP_DIR"

# Generate server config
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

# Add peers to server config
peers_count=$(jq '.peers | keys | length' "$CONFIG_DB")
if [ "$peers_count" -gt 0 ]; then
    info "Adding $peers_count peer(s) to server config"
    jq -r '.peers | to_entries[] |
        "[Peer]\nPublicKey = " + .value.public_key +
        "\nPresharedKey = " + .value.preshared_key +
        "\nAllowedIPs = " + (.value.ip | sub("/.*"; "")) + "/32\n"' "$CONFIG_DB" >> "$TMP_CONF"
else
    warn "No peers found in database"
fi

# Deploy if changed
CONF_PATH="$WG_DIR/$WG_CONF_FILE"
if [ -f "$CONF_PATH" ] && cmp -s "$TMP_CONF" "$CONF_PATH"; then
    success "Server config unchanged"
else
    cp "$TMP_CONF" "$CONF_PATH"
    success "Server configuration deployed: $CONF_PATH"
fi

# Generate peer configs
info "${CONFIG_EMOJI} Generating peer configurations..."
server_pub_key=$(get_db_value '.server.keys.public_key')
server_endpoint=$(get_db_value '.server.endpoint')
server_port=$(get_db_value '.server.port')

for peer in $(jq -r '.peers | keys | sort_by(.[4:] | tonumber) | .[]' "$CONFIG_DB"); do
    peer_data=$(jq -r --arg peer "$peer" '.peers[$peer]' "$CONFIG_DB")
    PEER_CONF_FILE="$SERVER_PEERS_DIR/${peer}.conf"

    cat > "$PEER_CONF_FILE" <<EOF
[Interface]
PrivateKey = $(echo "$peer_data" | jq -r '.private_key')
Address = $(echo "$peer_data" | jq -r '.ip')
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
I1 = $(get_protocol_value)
I2 = $(generate_cps_value)
I3 = $(generate_cps_value)
I4 = $(generate_cps_value)

[Peer]
PublicKey = $server_pub_key
PresharedKey = $(echo "$peer_data" | jq -r '.preshared_key')
Endpoint = $server_endpoint:$server_port
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

    success "Peer config generated: $PEER_CONF_FILE"
done

success "${CONFIG_EMOJI} Configuration generation completed"

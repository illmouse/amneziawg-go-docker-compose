#!/bin/bash

debug "${CONFIG_EMOJI} Generating server configuration..."

# Get server junk values
server_priv_key=$(get_db_value '.server.keys.private_key')
server_jc=$(get_db_value '.server.junk.jc')
server_jmin=$(get_db_value '.server.junk.jmin')
server_jmax=$(get_db_value '.server.junk.jmax')
server_s1=$(get_db_value '.server.junk.s1')
server_s2=$(get_db_value '.server.junk.s2')
server_s3=$(get_db_value '.server.junk.s3')
server_s4=$(get_db_value '.server.junk.s4')
server_h1=$(get_db_value '.server.junk.h1')
server_h2=$(get_db_value '.server.junk.h2')
server_h3=$(get_db_value '.server.junk.h3')
server_h4=$(get_db_value '.server.junk.h4')
server_hpk=$(get_db_value '.server.junk.header_protection_key')
server_cpa=$(get_db_value '.server.junk.content_padding_addition')
server_rat=$(get_db_value '.server.junk.rekey_after_time')
server_rto=$(get_db_value '.server.junk.rekey_timeout')
server_rej=$(get_db_value '.server.junk.reject_after_time')
server_kat=$(get_db_value '.server.junk.keepalive_timeout')
server_mha=$(get_db_value '.server.junk.max_handshake_attempts')
server_rt=$(get_db_value '.server.junk.random_trailers')
server_dc=$(get_db_value '.server.junk.disable_cookies')

[ -z "$server_priv_key" ] && error "Server private key not found in database"

# Append an optional parameter line to a config if its value is non-empty.
# Usage: emit_awg31_param <output_file> <param_name> <value>
# Always returns 0 — safe under `set -e` when the value is empty.
emit_awg31_param() {
    local out="$1" param="$2" value="$3"
    if [ -n "$value" ]; then
        printf "%s = %s\n" "$param" "$value" >> "$out"
    fi
    return 0
}

TMP_CONF="$TMP_DIR/$WG_CONF_FILE"

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
S3 = $server_s3
S4 = $server_s4
H1 = $server_h1
H2 = $server_h2
H3 = $server_h3
H4 = $server_h4

EOF

# AmneziaWG 3.1 optional parameters (server-side subset)
emit_awg31_param "$TMP_CONF" "HeaderProtectionKey" "$server_hpk"
emit_awg31_param "$TMP_CONF" "RandomTrailers" "$server_rt"
emit_awg31_param "$TMP_CONF" "DisableCookies" "$server_dc"

# Add peers to server config
peers_count=$(jq '.peers | keys | length' "$CONFIG_DB")
if [ "$peers_count" -gt 0 ]; then
    debug "Adding $peers_count peer(s) to server config"
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
    info "Server config unchanged"
else
    cp "$TMP_CONF" "$CONF_PATH"
    info "Server configuration deployed: $CONF_PATH"
fi

# Generate peer configs
debug "${CONFIG_EMOJI} Generating peer configurations..."
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
S3 = $server_s3
S4 = $server_s4
H1 = $server_h1
H2 = $server_h2
H3 = $server_h3
H4 = $server_h4
I1 = $(get_protocol_value)
I2 = $(generate_cps_value)
I3 = $(generate_cps_value)
I4 = $(generate_cps_value)
I5 = $(generate_cps_value)
EOF

    # AmneziaWG 3.1 optional parameters (client-side subset + shared ones)
    emit_awg31_param "$PEER_CONF_FILE" "HeaderProtectionKey" "$server_hpk"
    emit_awg31_param "$PEER_CONF_FILE" "ContentPaddingAddition" "$server_cpa"
    emit_awg31_param "$PEER_CONF_FILE" "RekeyAfterTime" "$server_rat"
    emit_awg31_param "$PEER_CONF_FILE" "RekeyTimeout" "$server_rto"
    emit_awg31_param "$PEER_CONF_FILE" "RejectAfterTime" "$server_rej"
    emit_awg31_param "$PEER_CONF_FILE" "KeepaliveTimeout" "$server_kat"
    emit_awg31_param "$PEER_CONF_FILE" "MaxHandshakeAttempts" "$server_mha"
    emit_awg31_param "$PEER_CONF_FILE" "RandomTrailers" "$server_rt"
    emit_awg31_param "$PEER_CONF_FILE" "DisableCookies" "$server_dc"

    cat >> "$PEER_CONF_FILE" <<EOF

[Peer]
PublicKey = $server_pub_key
PresharedKey = $(echo "$peer_data" | jq -r '.preshared_key')
Endpoint = $server_endpoint:$server_port
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

    success "Peer config generated: $PEER_CONF_FILE"
done

debug "${CONFIG_EMOJI} Configuration generation completed"

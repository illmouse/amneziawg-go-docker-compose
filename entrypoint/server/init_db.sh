#!/bin/bash

#############################################
# Initialize a fresh clean configuration DB
#############################################
init_config_db() {
    debug "Initializing new configuration database..."

    mkdir -p "$WG_DIR"

    cat > "$CONFIG_DB" <<EOF
{
  "server": {
    "interface": "$WG_IFACE",
    "address": "$WG_ADDRESS",
    "port": $WG_PORT,
    "endpoint": "$WG_ENDPOINT",
    "junk": {
      "jc": $Jc,
      "jmin": $Jmin,
      "jmax": $Jmax,
      "s1": $S1,
      "s2": $S2,
      "s3": $S3,
      "s4": $S4,
      "h1": "$H1",
      "h2": "$H2",
      "h3": "$H3",
      "h4": "$H4",
      "header_protection_key": "$HeaderProtectionKey",
      "content_padding_addition": "$ContentPaddingAddition",
      "rekey_after_time": "$RekeyAfterTime",
      "rekey_timeout": "$RekeyTimeout",
      "reject_after_time": "$RejectAfterTime",
      "keepalive_timeout": "$KeepaliveTimeout",
      "max_handshake_attempts": "$MaxHandshakeAttempts",
      "random_trailers": "$RandomTrailers",
      "disable_cookies": "$DisableCookies"
    },
    "keys": {
      "private_key": "",
      "public_key": ""
    }
  },
  "peers": {},
  "meta": {
    "version": "1.0",
    "last_updated": "$(date -Iseconds)"
  }
}
EOF

    success "New configuration database created at $CONFIG_DB"
}

#############################################
# Validate or repair existing DB
#############################################
validate_or_repair_db() {
    if [ ! -f "$CONFIG_DB" ]; then
        warn "Configuration database missing: $CONFIG_DB"
        init_config_db
        return
    fi

    if [ ! -s "$CONFIG_DB" ]; then
        error "Configuration database is empty: $CONFIG_DB"
        init_config_db
        return
    fi

    success "Configuration database valid"
}

#############################################
# Update DB with current env values
#############################################
update_config_db() {
    debug "Updating configuration database from environment..."

    TMP_FILE=$(mktemp)

    jq \
        --arg iface "$WG_IFACE" \
        --arg addr "$WG_ADDRESS" \
        --argjson port "$WG_PORT" \
        --arg endpoint "$WG_ENDPOINT" \
        --argjson jc "$Jc" \
        --argjson jmin "$Jmin" \
        --argjson jmax "$Jmax" \
        --argjson s1 "$S1" \
        --argjson s2 "$S2" \
        --argjson s3 "$S3" \
        --argjson s4 "$S4" \
        --arg h1 "$H1" \
        --arg h2 "$H2" \
        --arg h3 "$H3" \
        --arg h4 "$H4" \
        --arg hpk "$HeaderProtectionKey" \
        --arg cpa "$ContentPaddingAddition" \
        --arg rat "$RekeyAfterTime" \
        --arg rto "$RekeyTimeout" \
        --arg rej "$RejectAfterTime" \
        --arg kat "$KeepaliveTimeout" \
        --arg mha "$MaxHandshakeAttempts" \
        --arg rt "$RandomTrailers" \
        --arg dc "$DisableCookies" \
        --arg timestamp "$(date -Iseconds)" \
    '
    .server.interface = $iface |
    .server.address = $addr |
    .server.port = $port |
    .server.endpoint = $endpoint |
    .server.junk.jc = $jc |
    .server.junk.jmin = $jmin |
    .server.junk.jmax = $jmax |
    .server.junk.s1 = $s1 |
    .server.junk.s2 = $s2 |
    .server.junk.s3 = $s3 |
    .server.junk.s4 = $s4 |
    .server.junk.h1 = $h1 |
    .server.junk.h2 = $h2 |
    .server.junk.h3 = $h3 |
    .server.junk.h4 = $h4 |
    .server.junk.header_protection_key = $hpk |
    .server.junk.content_padding_addition = $cpa |
    .server.junk.rekey_after_time = $rat |
    .server.junk.rekey_timeout = $rto |
    .server.junk.reject_after_time = $rej |
    .server.junk.keepalive_timeout = $kat |
    .server.junk.max_handshake_attempts = $mha |
    .server.junk.random_trailers = $rt |
    .server.junk.disable_cookies = $dc |
    .meta.last_updated = $timestamp
    ' "$CONFIG_DB" > "$TMP_FILE"

    mv "$TMP_FILE" "$CONFIG_DB"

    success "Configuration database updated"
}

#############################################
# MAIN EXECUTION
#############################################

validate_or_repair_db
update_config_db

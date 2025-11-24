#!/bin/sh

. /entrypoint/functions.sh
. /entrypoint/load_env.sh

CONFIG_DB="/etc/amneziawg/config.json"

#############################################
# Initialize a fresh clean configuration DB
#############################################
init_config_db() {
    info "Initializing new configuration database..."

    mkdir -p /etc/amneziawg

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
      "h1": $H1,
      "h2": $H2,
      "h3": $H3,
      "h4": $H4
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

    # DB missing
    if [ ! -f "$CONFIG_DB" ]; then
        warning "Configuration database missing: $CONFIG_DB"
        init_config_db
        return
    fi

    # DB empty
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
    info "Updating configuration database from environment..."

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
        --argjson h1 "$H1" \
        --argjson h2 "$H2" \
        --argjson h3 "$H3" \
        --argjson h4 "$H4" \
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
    .server.junk.h1 = $h1 |
    .server.junk.h2 = $h2 |
    .server.junk.h3 = $h3 |
    .server.junk.h4 = $h4 |
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

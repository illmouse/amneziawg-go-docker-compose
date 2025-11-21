#!/bin/sh

. /entrypoint/functions.sh
. /entrypoint/load_env.sh

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
      "jc": $AWG_JC,
      "jmin": $AWG_JMIN,
      "jmax": $AWG_JMAX,
      "s1": $AWG_S1,
      "s2": $AWG_S2,
      "h1": $AWG_H1,
      "h2": $AWG_H2,
      "h3": $AWG_H3,
      "h4": $AWG_H4
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
# Validate or repair existing DB (original logic)
#############################################
validate_or_repair_db() {

    # DB missing
    if [ ! -f "$CONFIG_DB" ]; then
        error "Configuration database missing: $CONFIG_DB"
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

    # Server config
    set_db_field "server.iface" "$WG_IFACE"
    set_db_field "server.address" "$WG_ADDRESS"
    set_db_field "server.port" "$WG_PORT"
    set_db_field "server.endpoint" "$WG_ENDPOINT"

    # Keys — only update if provided by env
    set_db_field "server.keys.private_key" "$WG_PRIVATE_KEY"
    set_db_field "server.keys.public_key" "$WG_PUBLIC_KEY"

    # Junk parameters
    set_db_field "junk.Jc" "$Jc"
    set_db_field "junk.Jmin" "$Jmin"
    set_db_field "junk.Jmax" "$Jmax"
    set_db_field "junk.S1" "$S1"
    set_db_field "junk.S2" "$S2"
    set_db_field "junk.H1" "$H1"
    set_db_field "junk.H2" "$H2"
    set_db_field "junk.H3" "$H3"
    set_db_field "junk.H4" "$H4"

    success "Configuration database updated"
}

#############################################
# MAIN EXECUTION LOGIC
#############################################

validate_or_repair_db
update_config_db
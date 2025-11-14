#!/bin/sh
set -eu

. /entrypoint/functions.sh

# JSON database functions
init_config_db() {
    if [ ! -f "$CONFIG_DB" ]; then
        log "Initializing configuration database..."
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
    "last_updated": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  }
}
EOF
    fi
}

get_db_value() {
    local path="$1"
    jq -r "$path" "$CONFIG_DB" 2>/dev/null || echo ""
}

set_db_value() {
    local path="$1"
    local value="$2"
    jq "$path = $value" "$CONFIG_DB" > "$CONFIG_DB.tmp" && mv "$CONFIG_DB.tmp" "$CONFIG_DB"
}

update_server_config() {
    local needs_update=0
    
    # Check if server config needs update
    if [ "$(get_db_value '.server.interface')" != "$WG_IFACE" ]; then
        set_db_value '.server.interface' "\"$WG_IFACE\""
        needs_update=1
    fi
    
    if [ "$(get_db_value '.server.address')" != "$WG_ADDRESS" ]; then
        set_db_value '.server.address' "\"$WG_ADDRESS\""
        needs_update=1
    fi
    
    if [ "$(get_db_value '.server.port')" != "$WG_PORT" ]; then
        set_db_value '.server.port' "$WG_PORT"
        needs_update=1
    fi
    
    if [ "$(get_db_value '.server.endpoint')" != "$WG_ENDPOINT" ]; then
        set_db_value '.server.endpoint' "\"$WG_ENDPOINT\""
        needs_update=1
    fi
    
    # Check junk parameters
    local current_jc=$(get_db_value '.server.junk.jc')
    if [ "$current_jc" != "$Jc" ]; then
        set_db_value '.server.junk.jc' "$Jc"
        needs_update=1
    fi
    
    local current_jmin=$(get_db_value '.server.junk.jmin')
    if [ "$current_jmin" != "$Jmin" ]; then
        set_db_value '.server.junk.jmin' "$Jmin"
        needs_update=1
    fi
    
    # Update other junk parameters...
    for param in jmax s1 s2 h1 h2 h3 h4; do
        local current_val=$(get_db_value ".server.junk.$param")
        local env_val=$(eval echo \$$(echo $param | tr '[:lower:]' '[:upper:]'))
        if [ "$current_val" != "$env_val" ]; then
            set_db_value ".server.junk.$param" "$env_val"
            needs_update=1
        fi
    done
    
    # Update timestamp if anything changed
    if [ "$needs_update" -eq 1 ]; then
        set_db_value '.meta.last_updated' "\"$(date -u +'%Y-%m-%dT%H:%M:%SZ')\""
        log "Server configuration updated in database"
    fi
    
    return $needs_update
}

# Main execution
init_config_db
update_server_config
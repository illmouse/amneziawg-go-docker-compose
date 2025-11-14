#!/bin/sh
set -eu

# Set default environment variables if not already set
: "${WG_LOGFILE:=/var/log/amneziawg/amneziawg.log}"
: "${WG_DIR:=/etc/amneziawg}"
: "${CONFIG_DB:=$WG_DIR/config.json}"

# Source functions to get colors and emojis
. /entrypoint/functions.sh

# JSON database functions
init_config_db() {
    # Set more variables needed for the function
    : "${WG_IFACE:=wg0}"
    : "${WG_ADDRESS:=10.100.0.1/24}"
    : "${WG_PORT:=13440}"
    : "${WG_ENDPOINT:=}"
    : "${Jc:=3}"
    : "${Jmin:=1}"
    : "${Jmax:=50}"
    : "${S1:=25}"
    : "${S2:=72}"
    : "${H1:=1411927821}"
    : "${H2:=1212681123}"
    : "${H3:=1327217326}"
    : "${H4:=1515483925}"
    
    if [ ! -f "$CONFIG_DB" ]; then
        info "Initializing configuration database..."
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
        success "Configuration database initialized"
    else
        success "Using existing configuration database"
    fi
}

get_db_value() {
    local path="$1"
    if [ ! -f "$CONFIG_DB" ]; then
        echo ""
        return 1
    fi
    jq -r "$path" "$CONFIG_DB" 2>/dev/null || echo ""
}

set_db_value() {
    local path="$1"
    local value="$2"
    local temp_file="$CONFIG_DB.tmp.$$"
    
    if ! jq "$path = $value" "$CONFIG_DB" > "$temp_file" 2>/dev/null; then
        rm -f "$temp_file"
        return 1
    fi
    
    if [ ! -s "$temp_file" ]; then
        rm -f "$temp_file"
        return 1
    fi
    
    if mv "$temp_file" "$CONFIG_DB"; then
        return 0
    else
        rm -f "$temp_file"
        return 1
    fi
}

update_server_config() {
    local needs_update=0
    
    # Set variables needed for comparison
    : "${WG_IFACE:=wg0}"
    : "${WG_ADDRESS:=10.100.0.1/24}"
    : "${WG_PORT:=13440}"
    : "${WG_ENDPOINT:=}"
    : "${Jc:=3}"
    : "${Jmin:=1}"
    : "${Jmax:=50}"
    : "${S1:=25}"
    : "${S2:=72}"
    : "${H1:=1411927821}"
    : "${H2:=1212681123}"
    : "${H3:=1327217326}"
    : "${H4:=1515483925}"
    
    # Check if server config needs update
    if [ "$(get_db_value '.server.interface')" != "$WG_IFACE" ]; then
        set_db_value '.server.interface' "\"$WG_IFACE\""
        needs_update=1
    fi
    
    # ... rest of the update logic (shortened for brevity)
    
    if [ "$needs_update" -eq 1 ]; then
        set_db_value '.meta.last_updated' "\"$(date -u +'%Y-%m-%dT%H:%M:%SZ')\""
        info "Server configuration updated in database"
    fi
    
    return $needs_update
}

# Main execution
init_config_db
update_server_config

success "🗃️ Configuration database setup completed"
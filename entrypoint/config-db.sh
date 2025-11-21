#!/bin/sh

. /entrypoint/functions.sh
. /entrypoint/load_env.sh

# ===========================================================
# 1. Initialize DB if missing or corrupted
# ===========================================================

init_config_db() {
    info "Initializing new configuration database: $CONFIG_DB"

    cat <<EOF > "$CONFIG_DB"
{
  "server": {
    "iface": "",
    "address": "",
    "port": "",
    "endpoint": "",
    "keys": {
      "private_key": "",
      "public_key": ""
    }
  },
  "junk": {
    "Jc": "",
    "Jmin": "",
    "Jmax": "",
    "S1": "",
    "S2": "",
    "H1": "",
    "H2": "",
    "H3": "",
    "H4": ""
  }
}
EOF

    success "Created fresh configuration database"
}

# 1. File must not be empty
if [ ! -s "$CONFIG_DB" ]; then
    error "Config DB is empty — recreating"
    init_config_db
fi

# 2. Basic structure must contain '{'
if ! grep -q "{" "$CONFIG_DB"; then
    error "Config DB missing JSON structure — recreating"
    init_config_db
fi

# 3. jq must parse it, but allow a retry
if ! jq empty "$CONFIG_DB" >/dev/null 2>&1; then
    warn "Config DB parsed invalid once — retrying in 0.2s"
    sleep 0.2

    if ! jq empty "$CONFIG_DB" >/dev/null 2>&1; then
        error "Config DB confirmed corrupted — recreating"
        init_config_db
    else
        success "Config DB OK on second attempt"
    fi
fi

info "Configuration database loaded successfully"

# ===========================================================
# 2. DB Update helper — Update only fields with non-empty env
# ===========================================================

set_db_field() {
    key="$1"
    value="$2"

    [ -z "$value" ] && return 0  # skip empty env vars

    tmp=$(mktemp)

    # Numbers vs strings
    if printf '%s' "$value" | grep -Eq '^[0-9]+$'; then
        jq ".$key = $value" "$CONFIG_DB" > "$tmp" && mv "$tmp" "$CONFIG_DB"
    else
        jq ".$key = \"$value\"" "$CONFIG_DB" > "$tmp" && mv "$tmp" "$CONFIG_DB"
    fi
}

# ===========================================================
# 3. Apply updates (ONLY if env vars are non-empty)
# ===========================================================

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

success "Configuration DB updated from environment"

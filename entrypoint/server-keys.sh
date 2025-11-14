#!/bin/sh
set -eu

. /entrypoint/functions.sh

ensure_server_keys() {
    local server_priv="$KEYS_DIR/server_privatekey"
    local server_pub="$KEYS_DIR/server_publickey"
    
    # Generate keys if they don't exist
    if [ ! -s "$server_priv" ]; then
        log "Generating server private key..."
        SERVER_PRIV_KEY=$(gen_key)
        echo "$SERVER_PRIV_KEY" > "$server_priv"
        set_db_value '.server.keys.private_key' "\"$SERVER_PRIV_KEY\""
    else
        SERVER_PRIV_KEY=$(cat "$server_priv")
        # Update DB if key exists but not in DB
        if [ -z "$(get_db_value '.server.keys.private_key')" ]; then
            set_db_value '.server.keys.private_key' "\"$SERVER_PRIV_KEY\""
        fi
    fi
    
    if [ ! -s "$server_pub" ]; then
        log "Deriving server public key..."
        SERVER_PUB_KEY=$(pub_from_priv "$SERVER_PRIV_KEY")
        echo "$SERVER_PUB_KEY" > "$server_pub"
        set_db_value '.server.keys.public_key' "\"$SERVER_PUB_KEY\""
    else
        SERVER_PUB_KEY=$(cat "$server_pub")
        if [ -z "$(get_db_value '.server.keys.public_key')" ]; then
            set_db_value '.server.keys.public_key' "\"$SERVER_PUB_KEY\""
        fi
    fi
    
    export SERVER_PRIV_KEY SERVER_PUB_KEY
}

ensure_server_keys
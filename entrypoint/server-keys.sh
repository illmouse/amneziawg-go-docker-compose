#!/bin/sh

. /entrypoint/functions.sh

log "Generating server keys..."

log "Getting private key from database"
current_priv_key=$(get_db_value '.server.keys.private_key')

if [ -z "$current_priv_key" ] || [ "$current_priv_key" = "null" ] || [ "$current_priv_key" = "" ]; then
    log "Generating new server private key..."
    SERVER_PRIV_KEY=$(gen_key)
    
    log "Storing private key in database..."
    if set_db_value '.server.keys.private_key' "\"$SERVER_PRIV_KEY\""; then
        log "✓ Server private key stored in database"
    else
        error "Failed to store server private key in database"
    fi
else
    log "Using existing server private key from database"
    SERVER_PRIV_KEY="$current_priv_key"
fi

log "Getting public key from database"
current_pub_key=$(get_db_value '.server.keys.public_key')

if [ -z "$current_pub_key" ] || [ "$current_pub_key" = "null" ] || [ "$current_pub_key" = "" ]; then
    log "Deriving server public key from private key..."
    SERVER_PUB_KEY=$(pub_from_priv "$SERVER_PRIV_KEY")
    
    log "Storing public key in database..."
    if set_db_value '.server.keys.public_key' "\"$SERVER_PUB_KEY\""; then
        log "✓ Server public key stored in database"
    else
        error "Failed to store server public key in database"
    fi
else
    log "Using existing server public key from database"
    SERVER_PUB_KEY="$current_pub_key"
fi

export SERVER_PRIV_KEY SERVER_PUB_KEY
log "Server keys setup completed"
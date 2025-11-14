#!/bin/sh

. /entrypoint/functions.sh

log "DEBUG: server-keys.sh - Starting execution"

log "DEBUG: Step 1 - Getting private key from database"
current_priv_key=$(get_db_value '.server.keys.private_key')
log "DEBUG: Retrieved private key: '${current_priv_key:0:50}'"

log "DEBUG: Step 2 - Checking if private key exists"
if [ -z "$current_priv_key" ] || [ "$current_priv_key" = "null" ] || [ "$current_priv_key" = "" ]; then
    log "Generating new server private key..."
    log "DEBUG: Step 2.1 - Calling gen_key()"
    SERVER_PRIV_KEY=$(gen_key)
    log "DEBUG: Generated private key: ${SERVER_PRIV_KEY:0:20}..."
    
    log "Storing private key in database..."
    log "DEBUG: Step 2.2 - Storing private key in DB"
    if set_db_value '.server.keys.private_key' "\"$SERVER_PRIV_KEY\""; then
        log "✓ Server private key stored in database"
    else
        error "Failed to store server private key in database"
    fi
else
    log "Using existing server private key from database"
    SERVER_PRIV_KEY="$current_priv_key"
fi

log "DEBUG: Step 3 - Getting public key from database"
current_pub_key=$(get_db_value '.server.keys.public_key')
log "DEBUG: Retrieved public key: '${current_pub_key:0:50}'"

log "DEBUG: Step 4 - Checking if public key exists"
if [ -z "$current_pub_key" ] || [ "$current_pub_key" = "null" ] || [ "$current_pub_key" = "" ]; then
    log "Deriving server public key from private key..."
    log "DEBUG: Step 4.1 - Calling pub_from_priv()"
    SERVER_PUB_KEY=$(pub_from_priv "$SERVER_PRIV_KEY")
    log "DEBUG: Derived public key: ${SERVER_PUB_KEY:0:20}..."
    
    log "Storing public key in database..."
    log "DEBUG: Step 4.2 - Storing public key in DB"
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
log "DEBUG: server-keys.sh - Completed successfully"
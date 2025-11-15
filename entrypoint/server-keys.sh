#!/bin/bash

. /entrypoint/functions.sh

info "${KEY_EMOJI} Generating server keys..."

info "Getting private key from database"
current_priv_key=$(get_db_value '.server.keys.private_key')

if [ -z "$current_priv_key" ] || [ "$current_priv_key" = "null" ] || [ "$current_priv_key" = "" ]; then
    info "Generating new server private key..."
    SERVER_PRIV_KEY=$(gen_key)
    
    info "Storing private key in database..."
    if set_db_value '.server.keys.private_key' "\"$SERVER_PRIV_KEY\""; then
        success "${KEY_EMOJI} Server private key stored in database"
    else
        error "Failed to store server private key in database"
    fi
else
    success "Using existing server private key from database"
    SERVER_PRIV_KEY="$current_priv_key"
fi

info "Getting public key from database"
current_pub_key=$(get_db_value '.server.keys.public_key')

if [ -z "$current_pub_key" ] || [ "$current_pub_key" = "null" ] || [ "$current_pub_key" = "" ]; then
    info "Deriving server public key from private key..."
    SERVER_PUB_KEY=$(pub_from_priv "$SERVER_PRIV_KEY")
    
    info "Storing public key in database..."
    if set_db_value '.server.keys.public_key' "\"$SERVER_PUB_KEY\""; then
        success "${KEY_EMOJI} Server public key stored in database"
    else
        error "Failed to store server public key in database"
    fi
else
    success "Using existing server public key from database"
    SERVER_PUB_KEY="$current_pub_key"
fi

export SERVER_PRIV_KEY SERVER_PUB_KEY
success "${KEY_EMOJI} Server keys setup completed"
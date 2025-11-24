#!/bin/bash
set -eu

create_dir() {
    mkdir -p "$WG_DIR" "$TMP_DIR" "$CLIENT_PEERS_DIR" "$SERVER_PEERS_DIR" 
}

create_dir
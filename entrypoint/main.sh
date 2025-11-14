#!/bin/sh
set -eu

# Global variables
export WG_DIR="/etc/amneziawg"
export TMP_DIR="/tmp/amneziawg"
export KEYS_DIR="$WG_DIR/keys"
export PEERS_DIR="$WG_DIR/peers"
export CONFIG_DB="$WG_DIR/config.json"
export WG_CONF_FILE="wg0.conf"
export WG_LOGFILE="/var/log/amneziawg/amneziawg.log"

log() { 
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*" | tee -a "$WG_LOGFILE" 
}

log "Starting container from modular entrypoint..."

# Source all scripts in order
. /entrypoint/init.sh
. /entrypoint/config-db.sh
. /entrypoint/server-keys.sh
. /entrypoint/peers.sh
. /entrypoint/generate-configs.sh
. /entrypoint/start-wireguard.sh

log "Container startup complete. Entering sleep..."
sleep infinity
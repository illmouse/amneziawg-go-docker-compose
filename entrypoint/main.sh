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

# Simple log function for main script
log() { 
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*" | tee -a "$WG_LOGFILE" 
}

error() {
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] ERROR: $*" | tee -a "$WG_LOGFILE"
    exit 1
}

# Trap to catch any exits
trap 'log "TRAP: Script exiting with code: $?"' EXIT

log "Starting container from modular entrypoint..."

# Source and execute all scripts in order
log "=== Starting setup process ==="

log "1. Initializing environment..."
. /entrypoint/init.sh

log "2. Initializing configuration database..."
. /entrypoint/config-db.sh

log "3. Generating server keys..."
. /entrypoint/server-keys.sh

log "4. Managing peers..."
. /entrypoint/peers.sh

log "5. Generating configurations..."
. /entrypoint/generate-configs.sh

log "6. Starting WireGuard..."
. /entrypoint/start-wireguard.sh

log "=== All setup steps completed successfully ==="
log "Container startup complete. Entering sleep..."

# Keep container running
while true; do
    sleep 3600
done
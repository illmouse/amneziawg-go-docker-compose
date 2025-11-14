#!/bin/sh
set -eu

# Global variables
export WG_DIR="/etc/amneziawg"
export TMP_DIR="/tmp/amneziawg"
export PEERS_DIR="$WG_DIR/peers"
export CONFIG_DB="$WG_DIR/config.json"
export WG_CONF_FILE="wg0.conf"
export WG_LOGFILE="/var/log/amneziawg/amneziawg.log"

# Source functions first to get colors and emojis
. /entrypoint/functions.sh

# Trap to catch any exits
trap 'log "Script exiting with code: $?"' EXIT

success "🚀 Starting container from modular entrypoint..."

# Source and execute all scripts in order
info "🌈 === Starting setup process ==="

info "1. 📁 Initializing environment..."
. /entrypoint/init.sh

info "2. 🗃️ Initializing configuration database..."
. /entrypoint/config-db.sh

info "3. ${KEY_EMOJI} Generating server keys..."
. /entrypoint/server-keys.sh

info "4. ${PEER_EMOJI} Managing peers..."
. /entrypoint/peers.sh

info "5. ${CONFIG_EMOJI} Generating configurations..."
. /entrypoint/generate-configs.sh

info "6. ${SECURITY_EMOJI} Fixing permissions..."
fix_permissions

info "7. ${NETWORK_EMOJI} Starting WireGuard..."
. /entrypoint/start-wireguard.sh

success "🎉 === All setup steps completed successfully ==="
success "🏁 Container startup complete. Entering sleep..."

# Keep container running
while true; do
    sleep infinity
done
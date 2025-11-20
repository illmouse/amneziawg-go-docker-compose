#!/bin/bash
set -eu

# Load environment variables
. /entrypoint/load_env.sh

# Source functions first to get colors and emojis
. /entrypoint/functions.sh

# Trap to catch any exits
trap 'log "Script exiting with code: $?"' EXIT

success "🚀 Starting container in ${WG_MODE:-server} mode..."

if [ "${WG_MODE:-server}" = "server" ]; then
    info "🌈 === Starting SERVER setup process ==="
    
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

    success "🎉 === Server setup completed successfully ==="
    
elif [ "${WG_MODE:-server}" = "client" ]; then
    info "🌈 === Starting CLIENT setup process ==="
    
    info "1. 📁 Initializing environment..."
    . /entrypoint/init.sh

    info "2. 🔍 Setting up client mode..."
    . /entrypoint/client-mode.sh

    info "3. ${SECURITY_EMOJI} Fixing permissions..."
    fix_permissions

    info "4. ${NETWORK_EMOJI} Starting WireGuard client..."
    . /entrypoint/start-wireguard.sh

    info "5. 🦑 Starting Squid proxy (if enabled)..."
    start_squid

    success "🎉 === Client setup completed successfully ==="
    
else
    error "Unknown WG_MODE: $WG_MODE. Use 'server' or 'client'"
fi

# Start unified monitoring in background
info "🚀 Starting unified monitoring system..."
/entrypoint/unified-monitor.sh >>/var/log/amneziawg/unified-monitor.log 2>&1 &

success "🏁 Container startup complete. Entering sleep..."

# Keep container running
while true; do
    sleep infinity
done

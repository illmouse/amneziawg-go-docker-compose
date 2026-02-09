#!/bin/bash
set -eu

# Source shared libraries
. /entrypoint/lib/env.sh
. /entrypoint/lib/functions.sh
. /entrypoint/lib/config_parser.sh

# Trap to catch any exits
trap 'log_message $LOG_INFO "$BLUE" "$INFO_EMOJI" "Script exiting with code: $?"' EXIT

# Validate environment before proceeding
info "Validating environment..."
validate_environment

success "Starting container in ${WG_MODE} mode..."

if [ "${WG_MODE}" = "server" ]; then
    info "=== Starting SERVER setup process ==="

    info "1. Initializing environment..."
    ensure_directories

    info "2. ${CONFIG_EMOJI} Initializing configuration database..."
    . /entrypoint/server/init_db.sh

    info "3. ${KEY_EMOJI} Generating server keys..."
    . /entrypoint/server/keys.sh

    info "4. ${PEER_EMOJI} Managing peers..."
    . /entrypoint/server/peers.sh

    info "5. ${CONFIG_EMOJI} Generating configurations..."
    . /entrypoint/server/generate_configs.sh

    info "6. ${SECURITY_EMOJI} Fixing permissions..."
    fix_permissions

    info "7. ${NETWORK_EMOJI} Starting WireGuard..."
    . /entrypoint/server/start.sh

    success "=== Server setup completed successfully ==="

    # Start server monitor in background
    /entrypoint/server/monitor.sh 2>/dev/null &

elif [ "${WG_MODE}" = "client" ]; then
    info "=== Starting CLIENT setup process ==="

    info "1. Initializing environment..."
    ensure_directories

    info "2. ${CONFIG_EMOJI} Setting up client mode..."
    . /entrypoint/client/assemble_config.sh

    info "3. ${SECURITY_EMOJI} Fixing permissions..."
    fix_permissions

    info "4. ${NETWORK_EMOJI} Starting WireGuard client..."
    . /entrypoint/client/start.sh

    info "5. Starting proxy (if enabled)..."
    . /entrypoint/client/proxy.sh

    success "=== Client setup completed successfully ==="

    # Start client monitor in background
    /entrypoint/client/monitor.sh 2>/dev/null &

else
    error "Unknown WG_MODE: $WG_MODE. Use 'server' or 'client'"
fi

success "Container startup complete. Entering sleep..."

# Keep container running
while true; do
    sleep infinity
done

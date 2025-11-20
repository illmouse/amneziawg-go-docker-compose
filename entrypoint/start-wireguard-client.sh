#!/bin/bash
set -eu

. /entrypoint/functions.sh
. /entrypoint/load_env.sh

CLIENT_CONF="$TMP_DIR/$WG_CONF_FILE"

if [ ! -f "$CLIENT_CONF" ]; then
    error "Client configuration not found: $CLIENT_CONF. Did client-mode.sh run?"
fi

info "🌐 Starting WireGuard interface $WG_IFACE in CLIENT mode..."
wg-quick up "$CLIENT_CONF"

info "🔵 Setting up client routing..."
setup_client_routing

success "✅ Client WireGuard interface $WG_IFACE is up and routing configured"

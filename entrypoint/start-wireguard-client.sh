#!/bin/bash
set -eu

. /entrypoint/functions.sh
. /entrypoint/load_env.sh

info "🌐 Starting WireGuard interface $WG_IFACE in CLIENT mode..."

# Load client configuration (generated in client-mode.sh)
wg-quick up "$WG_IFACE"

info "🔵 Setting up client routing..."
setup_client_routing

success "✅ Client WireGuard interface $WG_IFACE is up and routing configured"

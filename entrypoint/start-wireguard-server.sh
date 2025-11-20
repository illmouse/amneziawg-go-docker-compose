#!/bin/bash
set -eu

. /entrypoint/functions.sh
. /entrypoint/load_env.sh

info "🌐 Starting WireGuard interface $WG_IFACE in SERVER mode..."

# Launch WireGuard
wg-quick up "$WG_IFACE"

success "✅ WireGuard server interface $WG_IFACE is up"

#!/bin/sh

. /entrypoint/functions.sh

info "${NETWORK_EMOJI} Starting WireGuard interface $WG_IFACE in CLIENT mode..."

info "Starting amneziawg-go on $WG_IFACE..."
amneziawg-go "$WG_IFACE" >>"$WG_LOGFILE" 2>&1 &
sleep 2

info "CLIENT MODE: Loading client configuration into $WG_IFACE..."
if ! awg setconf "$WG_IFACE" "$WG_DIR/$WG_CONF_FILE" >>"$WG_LOGFILE" 2>&1; then
    error "Failed to load client WireGuard configuration"
fi

info "Bringing client interface up..."
ip link set up dev "$WG_IFACE" >>"$WG_LOGFILE" 2>&1

if [ -n "$WG_ADDRESS" ]; then
    info "Assigning client address $WG_ADDRESS to $WG_IFACE..."
    ip address add dev "$WG_IFACE" "$WG_ADDRESS" 2>>"$WG_LOGFILE" || true
fi

success "${NETWORK_EMOJI} Client setup complete. Interface $WG_IFACE is connected to peers."

# Setup routing to force all traffic through WireGuard
setup_wireguard_routing

# Verify the configuration was applied correctly
info "Verifying WireGuard configuration..."
sleep 2
if awg show "$WG_IFACE" >>"$WG_LOGFILE" 2>&1; then
    success "WireGuard configuration verified"
else
    warn "Could not verify configuration with 'awg show'"
fi

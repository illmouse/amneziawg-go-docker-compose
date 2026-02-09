#!/bin/bash

debug "${NETWORK_EMOJI} Starting WireGuard interface $WG_IFACE in CLIENT mode..."

start_wg_iface "$WG_IFACE"

debug "CLIENT MODE: Loading client configuration into $WG_IFACE..."
if ! awg setconf "$WG_IFACE" "$WG_DIR/$WG_CONF_FILE" >>"$WG_LOGFILE" 2>&1; then
    error "Failed to load client WireGuard configuration"
fi

debug "Bringing client interface up..."
ip link set up dev "$WG_IFACE" >>"$WG_LOGFILE" 2>&1

if [ -n "$WG_ADDRESS" ]; then
    debug "Assigning client address $WG_ADDRESS to $WG_IFACE..."
    ip address add dev "$WG_IFACE" "$WG_ADDRESS" 2>>"$WG_LOGFILE" || true
fi

success "${NETWORK_EMOJI} Client setup complete. Interface $WG_IFACE is connected to peers."

setup_client_routing

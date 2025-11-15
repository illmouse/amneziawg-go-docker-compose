#!/bin/bash

. /entrypoint/functions.sh

info "${NETWORK_EMOJI} Starting WireGuard interface $WG_IFACE..."

info "Starting amneziawg-go on $WG_IFACE..."
amneziawg-go "$WG_IFACE" >>"$WG_LOGFILE" 2>&1 &
sleep 2

info "Assigning address $WG_ADDRESS to $WG_IFACE..."
ip address add dev "$WG_IFACE" "$WG_ADDRESS" 2>>"$WG_LOGFILE" || true

info "Loading config into $WG_IFACE..."
if ! awg setconf "$WG_IFACE" "$WG_DIR/$WG_CONF_FILE" >>"$WG_LOGFILE" 2>&1; then
    warn "awg setconf failed, checking configuration file..."
    # Debug: show the config file contents
    if [ -f "$WG_DIR/$WG_CONF_FILE" ]; then
        debug "Configuration file contents:"
        cat "$WG_DIR/$WG_CONF_FILE" >>"$WG_LOGFILE"
    else
        error "Configuration file not found: $WG_DIR/$WG_CONF_FILE"
    fi
    error "Failed to load WireGuard configuration"
fi

info "Bringing interface up..."
ip link set up dev "$WG_IFACE" >>"$WG_LOGFILE" 2>&1

info "Adding iptables rules..."
DEF_IFACE=$(ip route | awk '/default/ {print $5; exit}')

# Enable forwarding/NAT through the same interface
iptables -t nat -A POSTROUTING -o "$DEF_IFACE" -j MASQUERADE 2>>"$WG_LOGFILE" || true
iptables -A FORWARD -i "$WG_IFACE" -j ACCEPT 2>>"$WG_LOGFILE" || true
iptables -A INPUT -i "$WG_IFACE" -j ACCEPT 2>>"$WG_LOGFILE" || true

success "${NETWORK_EMOJI} WireGuard setup complete. Interface $WG_IFACE is up."
info "Configuration database: $CONFIG_DB"
info "Peer configurations available in: $PEERS_DIR/"

# Verify the configuration was applied correctly
info "Verifying WireGuard configuration..."
sleep 2
awg show "$WG_IFACE" >>"$WG_LOGFILE" 2>&1 && success "WireGuard configuration verified" || warn "Could not verify configuration with 'awg show'"
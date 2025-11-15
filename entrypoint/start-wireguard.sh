#!/bin/sh

. /entrypoint/functions.sh

info "${NETWORK_EMOJI} Starting WireGuard interface $WG_IFACE..."

info "Starting amneziawg-go on $WG_IFACE..."
amneziawg-go "$WG_IFACE" >>"$WG_LOGFILE" 2>&1 &
sleep 2

# Different setup for server vs client mode
if [ "$WG_MODE" = "server" ]; then
    info "SERVER MODE: Assigning address $WG_ADDRESS to $WG_IFACE..."
    ip address add dev "$WG_IFACE" "$WG_ADDRESS" 2>>"$WG_LOGFILE" || true

    info "Loading server config into $WG_IFACE..."
    if ! awg setconf "$WG_IFACE" "$WG_DIR/$WG_CONF_FILE" >>"$WG_LOGFILE" 2>&1; then
        warn "awg setconf failed, checking configuration file..."
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

    success "${NETWORK_EMOJI} Server setup complete. Interface $WG_IFACE is up."
    info "Configuration database: $CONFIG_DB"
    info "Peer configurations available in: $PEERS_DIR/"

else
    # CLIENT MODE
    info "CLIENT MODE: Loading client configuration into $WG_IFACE..."
    
    # Debug: Show the configuration we're trying to load
    debug "Client configuration to be loaded:"
    cat "$WG_DIR/$WG_CONF_FILE" | while read line; do
        debug "  $line"
    done
    
    if ! awg setconf "$WG_IFACE" "$WG_DIR/$WG_CONF_FILE" >>"$WG_LOGFILE" 2>&1; then
        error "Failed to load client WireGuard configuration with awg setconf"
    fi

    info "Bringing client interface up..."
    ip link set up dev "$WG_IFACE" >>"$WG_LOGFILE" 2>&1

    # For client mode, set up the interface address if specified
    if [ -n "$WG_ADDRESS" ]; then
        info "Assigning client address $WG_ADDRESS to $WG_IFACE..."
        ip address add dev "$WG_IFACE" "$WG_ADDRESS" 2>>"$WG_LOGFILE" || true
    fi

    success "${NETWORK_EMOJI} Client setup complete. Interface $WG_IFACE is connected to peers."
    info "Using configuration from: $WG_DIR/$WG_CONF_FILE"
fi

# Verify the configuration was applied correctly
info "Verifying WireGuard configuration..."
sleep 3
if awg show "$WG_IFACE" >>"$WG_LOGFILE" 2>&1; then
    success "WireGuard configuration verified"
    
    # Show connection status
    info "Connection status:"
    awg show "$WG_IFACE" | while read line; do
        info "  $line"
    done
else
    warn "Could not verify configuration with 'awg show'"
fi
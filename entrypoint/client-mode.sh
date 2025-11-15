#!/bin/sh

. /entrypoint/functions.sh

info "🔍 Setting up AmneziaWG client mode..."

# Validate client mode requirements
if [ ! -d "$PEERS_DIR" ]; then
    error "Client mode requires peer configurations in $PEERS_DIR"
fi

# Find peer configuration files
peer_configs=$(find "$PEERS_DIR" -name "*.conf" -type f | sort)
if [ -z "$peer_configs" ]; then
    error "No peer configuration files found in $PEERS_DIR. Please add .conf files for the peers you want to connect to."
fi

info "Found $(echo "$peer_configs" | wc -l) peer configuration file(s)"

# Use the first peer configuration as the main interface config
main_peer_config=$(echo "$peer_configs" | head -1)
info "Using main peer configuration: $(basename "$main_peer_config")"

# Copy the main peer configuration to become the interface configuration
cp "$main_peer_config" "$WG_DIR/$WG_CONF_FILE"
success "Main peer configuration applied: $WG_DIR/$WG_CONF_FILE"

# Extract interface settings from the main config for validation
interface_private_key=$(grep -E '^PrivateKey\s*=' "$WG_DIR/$WG_CONF_FILE" | head -1 | cut -d'=' -f2 | tr -d ' ')
interface_address=$(grep -E '^Address\s*=' "$WG_DIR/$WG_CONF_FILE" | head -1 | cut -d'=' -f2 | tr -d ' ')

if [ -z "$interface_private_key" ]; then
    error "No PrivateKey found in peer configuration. Client mode requires a complete WireGuard configuration."
fi

if [ -z "$interface_address" ]; then
    warn "No Address found in interface section of peer configuration. This may cause routing issues."
else
    info "Client interface address: $interface_address"
fi

# Log the peers we'll be connecting to
info "Client will connect to the following peers:"
for config in $peer_configs; do
    peer_public_key=$(grep -E '^PublicKey\s*=' "$config" | head -1 | cut -d'=' -f2 | tr -d ' ')
    peer_endpoint=$(grep -E '^Endpoint\s*=' "$config" | head -1 | cut -d'=' -f2 | tr -d ' ')
    if [ -n "$peer_public_key" ]; then
        if [ -n "$peer_endpoint" ]; then
            info "  - $peer_public_key → $peer_endpoint"
        else
            info "  - $peer_public_key (no endpoint)"
        fi
    fi
done

# For client mode, we don't need server-specific settings
export WG_ADDRESS="$interface_address"
info "Client mode configured successfully"

# Create a simple health check file for client mode
cat > "$WG_DIR/client-healthcheck.sh" << 'EOF'
#!/bin/sh
# Health check for client mode - check if wg0 interface exists and has peers
if ip link show wg0 >/dev/null 2>&1; then
    if awg show wg0 2>/dev/null | grep -q "peer:"; then
        exit 0
    fi
fi
exit 1
EOF
chmod +x "$WG_DIR/client-healthcheck.sh"

success "🔍 Client mode setup completed"
#!/bin/bash

info "Setting up AmneziaWG client mode..."

# Validate client mode requirements
if [ ! -d "$CLIENT_PEERS_DIR" ]; then
    error "Client mode requires peer configurations in $CLIENT_PEERS_DIR"
fi

# Find peer configuration files
peer_configs=$(find "$CLIENT_PEERS_DIR" -name "*.conf" -type f | sort)
if [ -z "$peer_configs" ]; then
    error "No peer configuration files found in $CLIENT_PEERS_DIR"
fi

info "Found $(echo "$peer_configs" | wc -l) peer configuration file(s)"

# Get master peer if specified
MASTER_PEER=${MASTER_PEER:-}
master_peer_config=""
if [ -n "$MASTER_PEER" ]; then
    master_peer_config="$CLIENT_PEERS_DIR/$MASTER_PEER"
    if [ ! -f "$master_peer_config" ]; then
        warn "MASTER_PEER $MASTER_PEER specified but file not found"
        master_peer_config=""
    else
        info "Found master peer configuration at $master_peer_config"
    fi
fi

# Use master peer if available, otherwise use first peer
if [ -n "$master_peer_config" ]; then
    main_peer_config="$master_peer_config"
    info "Using master peer configuration: $(basename "$main_peer_config")"
else
    main_peer_config=$(echo "$peer_configs" | head -1)
    info "Using main peer configuration: $(basename "$main_peer_config")"
fi

if [ ! -f "$main_peer_config" ]; then
    error "Main peer configuration file not found: $main_peer_config"
fi

# Extract DNS servers from peer config
dns_servers=$(conf_get_value "DNS" "$main_peer_config")
if [ -n "$dns_servers" ]; then
    info "DNS servers from peer config: $dns_servers"
    export PEER_DNS_SERVERS="$dns_servers"
else
    info "No DNS servers specified in peer configuration"
fi

# Build the client config using the shared builder
info "Creating AmneziaWG configuration..."
build_client_config "$main_peer_config" "$WG_DIR/$WG_CONF_FILE"

# Test the configuration with a temporary interface
info "Testing WireGuard configuration..."

info "Creating test interface..."
if ! amneziawg-go test-interface; then
    error "Failed to create test interface"
    exit 1
fi

info "Testing configuration with awg setconf..."
if awg_output=$(awg setconf "test-interface" "$WG_DIR/$WG_CONF_FILE" 2>&1); then
    success "WireGuard configuration test passed"
else
    error "WireGuard configuration test failed:"
    echo "$awg_output" >&2
fi

info "Cleaning up test interface..."
ip link delete "test-interface" || true

success "Client configuration created successfully"

# Export client address if found in peer config
client_address=$(conf_get_value "Address" "$main_peer_config")
if [ -n "$client_address" ]; then
    export WG_ADDRESS="$client_address"
    info "Client interface address: $client_address"
fi

# Configure DNS if specified in peer config
if [ -n "${PEER_DNS_SERVERS:-}" ]; then
    info "Configuring DNS servers: $PEER_DNS_SERVERS"
    configure_dns "$PEER_DNS_SERVERS"
fi

success "Client mode setup completed"

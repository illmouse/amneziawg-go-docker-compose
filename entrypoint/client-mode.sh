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
    error "No peer configuration files found in $PEERS_DIR"
fi

info "Found $(echo "$peer_configs" | wc -l) peer configuration file(s)"

# Use the first peer configuration as the main interface config
main_peer_config=$(echo "$peer_configs" | head -1)
info "Using main peer configuration: $(basename "$main_peer_config")"

if [ ! -f "$main_peer_config" ]; then
    error "Main peer configuration file not found: $main_peer_config"
fi

# Check if Squid should be enabled
SQUID_ENABLE=${SQUID_ENABLE:-false}
SQUID_PORT=${SQUID_PORT:-3128}

if [ "$SQUID_ENABLE" = "true" ]; then
    info "🦑 Squid proxy enabled on port $SQUID_PORT"
    export SQUID_ENABLED=true
    export SQUID_PORT=$SQUID_PORT
else
    info "Squid proxy disabled"
    export SQUID_ENABLED=false
fi

# Extract DNS servers from peer config
dns_servers=$(grep "^DNS" "$main_peer_config" | head -1 | sed 's/^DNS[[:space:]]*=[[:space:]]*//' | tr -d '\r\n')
if [ -n "$dns_servers" ]; then
    info "DNS servers from peer config: $dns_servers"
    export PEER_DNS_SERVERS="$dns_servers"
else
    info "No DNS servers specified in peer configuration"
fi

# Extract junk parameters from peer config
extract_junk_param() {
    local param="$1"
    local default="$2"
    local value=$(grep -E "^${param}[[:space:]]*=" "$main_peer_config" | head -1 | sed "s/^${param}[[:space:]]*=[[:space:]]*//" | tr -d '\r\n')
    echo "${value:-$default}"
}

# Extract junk parameters from peer config
Jc=$(extract_junk_param "Jc" "3")
Jmin=$(extract_junk_param "Jmin" "1") 
Jmax=$(extract_junk_param "Jmax" "50")
S1=$(extract_junk_param "S1" "25")
S2=$(extract_junk_param "S2" "72")
H1=$(extract_junk_param "H1" "1411927821")
H2=$(extract_junk_param "H2" "1212681123")
H3=$(extract_junk_param "H3" "1327217326")
H4=$(extract_junk_param "H4" "1515483925")

info "Using junk parameters from peer configuration"

# Create a clean copy of the original file
cp "$main_peer_config" "$WG_DIR/$WG_CONF_FILE.orig"

# Modify to be awg-compatible: remove problematic parameters
sed -i '/^Address[[:space:]]*=/d' "$WG_DIR/$WG_CONF_FILE.orig"
sed -i '/^DNS[[:space:]]*=/d' "$WG_DIR/$WG_CONF_FILE.orig"

# Add ListenPort = 0 to Interface section
if ! grep -q "^ListenPort" "$WG_DIR/$WG_CONF_FILE.orig"; then
    sed -i '/^\[Interface\]/a ListenPort = 0' "$WG_DIR/$WG_CONF_FILE.orig"
fi

# Remove existing junk parameters
sed -i '/^Jc[[:space:]]*=/d' "$WG_DIR/$WG_CONF_FILE.orig"
sed -i '/^Jmin[[:space:]]*=/d' "$WG_DIR/$WG_CONF_FILE.orig"
sed -i '/^Jmax[[:space:]]*=/d' "$WG_DIR/$WG_CONF_FILE.orig"
sed -i '/^S1[[:space:]]*=/d' "$WG_DIR/$WG_CONF_FILE.orig"
sed -i '/^S2[[:space:]]*=/d' "$WG_DIR/$WG_CONF_FILE.orig"
sed -i '/^H1[[:space:]]*=/d' "$WG_DIR/$WG_CONF_FILE.orig"
sed -i '/^H2[[:space:]]*=/d' "$WG_DIR/$WG_CONF_FILE.orig"
sed -i '/^H3[[:space:]]*=/d' "$WG_DIR/$WG_CONF_FILE.orig"
sed -i '/^H4[[:space:]]*=/d' "$WG_DIR/$WG_CONF_FILE.orig"

# Remove junk parameters from Peer sections
sed -i '/^\[Peer\]/,/^\[/ { /^Jc[[:space:]]*=/d; /^Jmin[[:space:]]*=/d; /^Jmax[[:space:]]*=/d; /^S1[[:space:]]*=/d; /^S2[[:space:]]*=/d; /^H1[[:space:]]*=/d; /^H2[[:space:]]*=/d; /^H3[[:space:]]*=/d; /^H4[[:space:]]*=/d }' "$WG_DIR/$WG_CONF_FILE.orig"

# Add consistent junk parameters to Interface section
junk_temp=$(mktemp)
cat > "$junk_temp" << JUNK_PARAMS
Jc = $Jc
Jmin = $Jmin
Jmax = $Jmax
S1 = $S1
S2 = $S2
H1 = $H1
H2 = $H2
H3 = $H3
H4 = $H4
JUNK_PARAMS

sed -i "/^\[Interface\]/r $junk_temp" "$WG_DIR/$WG_CONF_FILE.orig"
rm -f "$junk_temp"

# Extract interface address for later assignment
interface_address=$(grep "^Address" "$main_peer_config" | head -1 | sed 's/^Address[[:space:]]*=[[:space:]]*//' | tr -d '\r\n')

# Test and use the configuration
if awg setconf "test-interface" "$WG_DIR/$WG_CONF_FILE.orig" 2>/dev/null; then
    mv "$WG_DIR/$WG_CONF_FILE.orig" "$WG_DIR/$WG_CONF_FILE"
    success "Client configuration created successfully"
else
    # Fallback: create minimal config
    warn "Using fallback configuration method"
    rm -f "$WG_DIR/$WG_CONF_FILE.orig"
    
    interface_private_key=$(grep "^PrivateKey" "$main_peer_config" | head -1 | sed 's/^PrivateKey[[:space:]]*=[[:space:]]*//' | tr -d '\r\n')
    
    cat > "$WG_DIR/$WG_CONF_FILE" << EOF
[Interface]
PrivateKey = $interface_private_key
ListenPort = 0
Jc = $Jc
Jmin = $Jmin
Jmax = $Jmax
S1 = $S1
S2 = $S2
H1 = $H1
H2 = $H2
H3 = $H3
H4 = $H4

EOF
    
    # Add peer sections
    in_peer_section=false
    peer_buffer=""
    
    while IFS= read -r line || [ -n "$line" ]; do
        line=$(printf "%s" "$line" | tr -d '\r')
        
        if [ "$line" = "[Peer]" ]; then
            if [ "$in_peer_section" = true ] && [ -n "$peer_buffer" ]; then
                echo "$peer_buffer" >> "$WG_DIR/$WG_CONF_FILE"
            fi
            peer_buffer="[Peer]"
            in_peer_section=true
        elif [ "$in_peer_section" = true ]; then
            if [ -n "$line" ] && echo "$line" | grep -qE '^\[[a-zA-Z]+\]'; then
                echo "$peer_buffer" >> "$WG_DIR/$WG_CONF_FILE"
                peer_buffer=""
                in_peer_section=false
            elif [ -n "$line" ] && ! echo "$line" | grep -qE '^(Jc|Jmin|Jmax|S1|S2|H1|H2|H3|H4)'; then
                key=$(echo "$line" | cut -d'=' -f1 | sed 's/[[:space:]]*$//')
                value=$(echo "$line" | cut -d'=' -f2- | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
                peer_buffer="$peer_buffer"$'\n'"$key = $value"
            fi
        fi
    done < "$main_peer_config"
    
    if [ -n "$peer_buffer" ]; then
        echo "$peer_buffer" >> "$WG_DIR/$WG_CONF_FILE"
    fi
fi

if [ -n "$interface_address" ]; then
    export WG_ADDRESS="$interface_address"
    info "Client interface address: $interface_address"
fi

# Configure DNS if specified in peer config
if [ -n "$PEER_DNS_SERVERS" ]; then
    info "Configuring DNS servers: $PEER_DNS_SERVERS"
    configure_dns "$PEER_DNS_SERVERS"
fi

# Setup Squid if enabled
if [ "$SQUID_ENABLED" = "true" ]; then
    setup_squid
fi

# Create health check
cat > "$WG_DIR/client-healthcheck.sh" << 'EOF'
#!/bin/sh
if ip link show wg0 >/dev/null 2>&1 && awg show wg0 2>/dev/null | grep -q "peer:"; then
    exit 0
fi
exit 1
EOF
chmod +x "$WG_DIR/client-healthcheck.sh"

success "🔍 Client mode setup completed"
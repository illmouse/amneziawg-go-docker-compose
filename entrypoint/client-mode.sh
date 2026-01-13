#!/bin/sh

. /entrypoint/functions.sh

info "🔍 Setting up AmneziaWG client mode..."

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
        log "⚠️ MASTER_PEER $MASTER_PEER specified but file not found"
        master_peer_config=""
    else
        info "✅ Using master peer configuration: $MASTER_PEER"
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

# Extract parameters we need
extract_param() {
    local param="$1"
    local value=$(grep -E "^${param}[[:space:]]*=" "$main_peer_config" | head -1 | sed "s/^${param}[[:space:]]*=[[:space:]]*//" | tr -d '\r\n')
    echo "$value"
}

# Extract all parameters in a loop
params="PrivateKey Jc Jmin Jmax S1 S2 H1 H2 H3 H4 I1 I2 I3 I4 I5 Address"
declare -A extracted_params
declare -A PROTOCOL_MAP=(
    ["DEFAULT"]="<b 0x5245474953544552207369703a676f6f676c652e636f6d205349502f322e300d0a5669613a205349502f322e302f554450203139322e3136382e3137312e343a353036303b6272616e63683d7a39684734624b3061393661653138633830306635306337343232666239610d0a4d61782d466f7277617264733a2037300d0a546f3a203c7369703a7573657240676f6f676c652e636f6d3e0d0a46726f6d3a203c7369703a7573657240676f6f676c652e636f6d3e3b7461673d373134393931303661396363656437630d0a43616c6c2d49443a2063313136376162646665333730626632653831336533663539626265623862300d0a435365713a20312052454749535445520d0a436f6e746163743a203c7369703a75736572403139322e3136382e3234342e3131333a353036303e0d0a557365722d4167656e743a204d6963726f5349502f332e302e300d0a457870697265733a20323336340d0a436f6e74656e742d4c656e6774683a20300d0a0d0a>"
    ["DNS"]="<b 0xd4ca6d64afbc2c56dcd32984080045000034cd5a00004011a3ffc0a80202b9248d90ab79003500200991c70701000001000000000000037777770272750000010001>"
    ["QUIC"]="<b 0xd4ca6d64afbc2c56dcd3298408004500050000004000401157a4c0a802028efb8ca3b6e201bb04ece346c30000000108ff4a4872b98928e903ab9c50004358a571c21fd637be1526485d949a4de85f699afc5b8a6381a3d470f0d0bd7163c97a7ef13ef044bf04be1e551a18d9a2db8b7bb19f0c4b79bfa664662180bffae9fda49cb42c361bcc7e468fb06c2a1d00ebe892184bc94e1bd51d12e5a0a50f588e7ecfb0ee303e50b4ef06fdca432907a134ca5f5323c92aa3eb104dc4a6da1a5f2e79fa97f7e94ae44b075f22624c1e97950c1bf96c2113459eca9401d3e4ece9d066291288a3726a5a31ae52b8083c268044dcf8562e4fc6ebd3d754c6d7afcf500aa6ca667ffb84fe324c5df4020205405420ac45d75272bb42187a19ce1c17b580224c2915f602f9d01967fec1a8f66a3267d8977b7a2222a75c40c45f268b755cc692ee0bba45d6df0a321ec5e0d61261d01aa000d8ca3912b7b2f31f6b161b4b4c5e310bd99c28dca3e7e27d290c2a4e8ca24fd218795d7022d0f7581370a2c605852798a6ad7c0ce51a28f8196af11b724e493601258b27806061d0833bbc4048df2ec557681256e58c193462bff900d8cc2696bb804062571ed9e030feb17a3cea4cf07e0a43147beacb6dc38e6fc127af5d61e2403cba6f68d6411edbc33e53f8ffd3f820fc4f404e0e9b58f7e13217fb45687df70af663c3f68f6d34b284454ee1051ae98bad4c4fe1812a1e81da76810bf371b72254300dbf7c7b436f358ca6e63f614886257f2fece203c57100afe0df5c521a0dbac3d46831c6a5673b83811222491ffb24c601a3a08ed9ed0167c977c4bdae99eca452b5f1ae35aa29e4229982c63aae7b96c6dd248fb5732f56ffeb9788e8fe4f2d27c956e383c2a2cbc610f19c22ebf2b8a322156be062782ed6a7e20c857fe3b80fee12ac70bf655829bca1cceaabbf12bec1f94c7a0d5f220a52854670c2cca7b228dbf4fa0b0b7b59e1344c0fd98ad8d033608cae715a52509d972bad21537acd2de6f06fe556e728154d736eca3b7a2eccdf287b91b02bdc344c91b2a1332b827a88a8e46320fe344a73da29a542938f8def2fd622ba012f7e244e297b795d1056bb09feb40832bd3afcd86c8c5e9e845e09c0d9486e5f26e1fb8df11cfc9cd843a23ec1e7ec82a024c13d9b903ea2ed75bb672bf6fd241b12acabb4f3f82b2bffbb64d9b19747770fa357e4e7c89d49f54c41e53d1105aac3e28baa9cc64584c1f12a7e9ef0b610963a67378bd031fdd442cdf6b69393bb98abc9000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000>"
)

for param in $params; do
    value=$(extract_param "$param")
    if [ -n "$value" ]; then
        extracted_params["$param"]="$value"
    fi
done

# --- Ensure I1-I5 exist ---------------------------------------------------
# I1: use Setting CSP protocol for peer if not defined
if [[ -z "${extracted_params[I1]+_}" ]]; then
    extracted_params["I1"]=$(get_protocol_value)
fi

# I2–I5: generate if not defined or missing
for i in {2..5}; do
    key="I$i"
    if [[ -z "${extracted_params[$key]+_}" || -z "${extracted_params[$key]}" ]]; then
        extracted_params["$key"]=$(generate_cps_value)
    fi
done

# --- Create the final configuration ----------------------------------------
info "Creating AmneziaWG configuration..."

cat > "$WG_DIR/$WG_CONF_FILE" << EOF
[Interface]
PrivateKey = ${extracted_params[PrivateKey]}
ListenPort = 0
EOF

# Add junk parameters if they exist
for param in Jc Jmin Jmax S1 S2 H1 H2 H3 H4 I1 I2 I3 I4 I5; do
    if [[ -n "${extracted_params[$param]+_}" ]]; then
        printf "%s = %s\n" "$param" "${extracted_params[$param]}" >> "$WG_DIR/$WG_CONF_FILE"
    fi
done

# Optional blank line at the end
echo "" >> "$WG_DIR/$WG_CONF_FILE"

# Extract and add peer sections
in_peer_section=false
peer_buffer=""

while IFS= read -r line || [ -n "$line" ]; do
    line=$(printf "%s" "$line" | tr -d '\r')
    
    if [ "$line" = "[Peer]" ]; then
        if [ "$in_peer_section" = true ] && [ -n "$peer_buffer" ]; then
            echo "$peer_buffer" >> "$WG_DIR/$WG_CONF_FILE"
            echo "" >> "$WG_DIR/$WG_CONF_FILE"
        fi
        peer_buffer="[Peer]"
        in_peer_section=true
    elif [ "$in_peer_section" = true ]; then
        if [ -n "$line" ] && echo "$line" | grep -qE '^\[[a-zA-Z]+\]'; then
            echo "$peer_buffer" >> "$WG_DIR/$WG_CONF_FILE"
            echo "" >> "$WG_DIR/$WG_CONF_FILE"
            peer_buffer=""
            in_peer_section=false
        elif [ -n "$line" ] && ! echo "$line" | grep -qE '^(Address|DNS)'; then
            peer_buffer="$peer_buffer"$'\n'"$line"
        fi
    fi
done < "$main_peer_config"

if [ -n "$peer_buffer" ]; then
    echo "$peer_buffer" >> "$WG_DIR/$WG_CONF_FILE"
fi

# Test the configuration with a temporary interface
info "Testing WireGuard configuration..."

# Create test interface first
info "Creating test interface..."
if ! amneziawg-go test-interface; then
    error "Failed to create test interface"
    exit 1
fi

# Test the configuration
info "Testing configuration with awg setconf..."
if awg_output=$(awg setconf "test-interface" "$WG_DIR/$WG_CONF_FILE" 2>&1); then
    success "WireGuard configuration test passed"
else
    error "WireGuard configuration test failed:"
    echo "$awg_output" >&2
fi

# Remove test interface
info "Cleaning up test interface..."
ip link delete "test-interface" || true

success "Client configuration created successfully"

if [ -n "${extracted_params[Address]}" ]; then
    export WG_ADDRESS="${extracted_params[Address]}"
    info "Client interface address: ${extracted_params[Address]}"
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

success "🔍 Client mode setup completed"
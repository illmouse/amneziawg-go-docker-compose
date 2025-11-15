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

# Read the original peer configuration
if [ ! -f "$main_peer_config" ]; then
    error "Main peer configuration file not found: $main_peer_config"
fi

# Create a proper AmneziaWG configuration file that awg setconf will accept
info "Creating AmneziaWG-compatible configuration..."

# Extract junk parameters FROM THE PEER CONFIG, not from environment
extract_junk_param() {
    local param="$1"
    local default="$2"
    local value=$(grep -E "^${param}[[:space:]]*=" "$main_peer_config" | head -1 | sed "s/^${param}[[:space:]]*=[[:space:]]*//" | tr -d '\r\n')
    if [ -n "$value" ]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# Extract junk parameters from peer config with fallbacks
Jc=$(extract_junk_param "Jc" "3")
Jmin=$(extract_junk_param "Jmin" "1") 
Jmax=$(extract_junk_param "Jmax" "50")
S1=$(extract_junk_param "S1" "25")
S2=$(extract_junk_param "S2" "72")
H1=$(extract_junk_param "H1" "1411927821")
H2=$(extract_junk_param "H2" "1212681123")
H3=$(extract_junk_param "H3" "1327217326")
H4=$(extract_junk_param "H4" "1515483925")

info "Using junk parameters from peer configuration:"
debug "  Jc=$Jc, Jmin=$Jmin, Jmax=$Jmax"
debug "  S1=$S1, S2=$S2"
debug "  H1=$H1, H2=$H2, H3=$H3, H4=$H4"

# METHOD 1: Direct file copy and modification (most reliable)
info "Using direct file copy method..."

# First, create a clean copy of the original file
cp "$main_peer_config" "$WG_DIR/$WG_CONF_FILE.orig"

# Now modify it to be awg-compatible
# Remove problematic Interface parameters that awg doesn't understand
sed -i '/^Address[[:space:]]*=/d' "$WG_DIR/$WG_CONF_FILE.orig"
sed -i '/^DNS[[:space:]]*=/d' "$WG_DIR/$WG_CONF_FILE.orig"

# Add ListenPort = 0 to Interface section
if ! grep -q "^ListenPort" "$WG_DIR/$WG_CONF_FILE.orig"; then
    sed -i '/^\[Interface\]/a ListenPort = 0' "$WG_DIR/$WG_CONF_FILE.orig"
fi

# Remove existing junk parameters from Interface section (we'll add consistent ones)
sed -i '/^Jc[[:space:]]*=/d' "$WG_DIR/$WG_CONF_FILE.orig"
sed -i '/^Jmin[[:space:]]*=/d' "$WG_DIR/$WG_CONF_FILE.orig"
sed -i '/^Jmax[[:space:]]*=/d' "$WG_DIR/$WG_CONF_FILE.orig"
sed -i '/^S1[[:space:]]*=/d' "$WG_DIR/$WG_CONF_FILE.orig"
sed -i '/^S2[[:space:]]*=/d' "$WG_DIR/$WG_CONF_FILE.orig"
sed -i '/^H1[[:space:]]*=/d' "$WG_DIR/$WG_CONF_FILE.orig"
sed -i '/^H2[[:space:]]*=/d' "$WG_DIR/$WG_CONF_FILE.orig"
sed -i '/^H3[[:space:]]*=/d' "$WG_DIR/$WG_CONF_FILE.orig"
sed -i '/^H4[[:space:]]*=/d' "$WG_DIR/$WG_CONF_FILE.orig"

# Remove junk parameters from Peer sections (they don't belong there!)
sed -i '/^\[Peer\]/,/^\[/ { /^Jc[[:space:]]*=/d; /^Jmin[[:space:]]*=/d; /^Jmax[[:space:]]*=/d; /^S1[[:space:]]*=/d; /^S2[[:space:]]*=/d; /^H1[[:space:]]*=/d; /^H2[[:space:]]*=/d; /^H3[[:space:]]*=/d; /^H4[[:space:]]*=/d }' "$WG_DIR/$WG_CONF_FILE.orig"

# Add consistent junk parameters ONLY to Interface section
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

# Insert after [Interface] section
sed -i "/^\[Interface\]/r $junk_temp" "$WG_DIR/$WG_CONF_FILE.orig"
rm -f "$junk_temp"

# Validate the private key in the original file before proceeding
info "Validating private key..."
original_private_key_line=$(grep "^PrivateKey" "$main_peer_config")
if [ -z "$original_private_key_line" ]; then
    error "No PrivateKey found in original configuration"
fi

# Extract key using a more reliable method
interface_private_key=$(echo "$original_private_key_line" | sed 's/^PrivateKey[[:space:]]*=[[:space:]]*//' | tr -d '\r\n')
key_length=$(printf "%s" "$interface_private_key" | wc -c)

debug "Original private key line: '$original_private_key_line'"
debug "Extracted private key: '$interface_private_key'"
debug "Key length: $key_length"

if [ "$key_length" -ne 44 ]; then
    warn "Private key length is $key_length (expected 44). This may cause issues."
fi

# Also validate the key in our modified file
modified_private_key_line=$(grep "^PrivateKey" "$WG_DIR/$WG_CONF_FILE.orig")
modified_private_key=$(echo "$modified_private_key_line" | sed 's/^PrivateKey[[:space:]]*=[[:space:]]*//' | tr -d '\r\n')
modified_key_length=$(printf "%s" "$modified_private_key" | wc -c)

if [ "$modified_key_length" -ne 44 ]; then
    error "Private key corrupted during processing. Original: $key_length, Modified: $modified_key_length"
fi

# Extract interface address for later assignment
interface_address=$(grep "^Address" "$main_peer_config" | head -1 | sed 's/^Address[[:space:]]*=[[:space:]]*//' | tr -d '\r\n')

# Test the configuration with awg setconf
info "Testing configuration with awg setconf..."
if timeout 5s awg setconf "test-interface" "$WG_DIR/$WG_CONF_FILE.orig" 2>/dev/null; then
    success "Configuration test passed"
    mv "$WG_DIR/$WG_CONF_FILE.orig" "$WG_DIR/$WG_CONF_FILE"
else
    # If awg setconf fails, try the manual method
    warn "awg setconf test failed, using manual configuration method..."
    rm -f "$WG_DIR/$WG_CONF_FILE.orig"
    
    # METHOD 2: Manual interface configuration
    info "Using manual interface configuration..."
    
    # Create a minimal valid config with junk parameters from peer config
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
    
    # Extract and add peer sections manually (without junk parameters)
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
                # New section started
                if [ -n "$peer_buffer" ]; then
                    echo "$peer_buffer" >> "$WG_DIR/$WG_CONF_FILE"
                    echo "" >> "$WG_DIR/$WG_CONF_FILE"
                fi
                peer_buffer=""
                in_peer_section=false
            elif [ -n "$line" ] && ! echo "$line" | grep -qE '^(Jc|Jmin|Jmax|S1|S2|H1|H2|H3|H4)'; then
                # Clean the line (skip junk params since they don't belong in Peer sections)
                key=$(echo "$line" | cut -d'=' -f1 | sed 's/[[:space:]]*$//')
                value=$(echo "$line" | cut -d'=' -f2- | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
                peer_buffer="$peer_buffer"$'\n'"$key = $value"
            fi
        fi
    done < "$main_peer_config"
    
    # Add final peer section
    if [ -n "$peer_buffer" ]; then
        echo "$peer_buffer" >> "$WG_DIR/$WG_CONF_FILE"
    fi
fi

success "AmneziaWG client configuration created: $WG_DIR/$WG_CONF_FILE"

# Final validation
if [ ! -f "$WG_DIR/$WG_CONF_FILE" ] || [ ! -s "$WG_DIR/$WG_CONF_FILE" ]; then
    error "Failed to create valid configuration file"
fi

if [ -z "$interface_address" ]; then
    warn "No Address found in interface section of client configuration."
else
    info "Client interface address: $interface_address"
    export WG_ADDRESS="$interface_address"
fi

# Log the final configuration summary
info "Final client configuration uses junk parameters from peer config"
debug "Junk parameters in Interface section only (not in Peer sections)"

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
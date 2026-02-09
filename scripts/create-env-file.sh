#!/bin/bash
set -e

# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/functions.sh"

setup_env() {
    log "Creating .env file..."
    

    log "Creating .env file with generated obfuscation values"
    
    # Set default values as fallback if variables aren't exported from setup.sh
    
    
    # Generate random values for obfuscation parameters
    Jc=$(get_random_int 3 10)
    Jmin=1
    Jmax=50
    S1=$(get_random_junk_size)
    S2=$(get_random_junk_size)
    H1=$(get_random_header)
    H2=$(get_random_header)
    H3=$(get_random_header)
    H4=$(get_random_header)
    
    # Create .env file directly from template inside script with all values
    cat > "$SCRIPT_DIR/.env" << EOF
# .env
# Mandatory params

# Public endpoint
WG_ENDPOINT=$WG_ENDPOINT

# Optional default params

# Proxy config
PROXY_ENABLED=$PROXY_ENABLED
PROXY_PORT_HTTP=$PROXY_PORT_HTTP
PROXY_PORT_SOCKS5=$PROXY_PORT_SOCKS5

# Name of the VPN interface inside the container
WG_IFACE=$WG_IFACE
# Server IP and subnet
WG_ADDRESS=$WG_ADDRESS
# VPN port to accept connections
WG_PORT=$WG_PORT
# Number of peers to create
WG_PEER_COUNT=$WG_PEER_COUNT
# Client mode: Connects to peers using configs from config/client_peers/
WG_MODE=$WG_MODE
# Master peer - peer config filename that will be main peer
# if set - once become available tunnel will always be switched to this peer
MASTER_PEER=
# log level to use - ERROR,INFO,WARN,DEBUG
LOG_LEVEL=INFO
# UDP protocol to be used for obfuscation. Available options: DEFAULT, DNS, QUIC
UDP_SIGNATURE=DEFAULT

# AmneziaWG tunable parameters
Jc=$Jc
Jmin=$Jmin
Jmax=$Jmax
S1=$S1
S2=$S2
H1=$H1
H2=$H2
H3=$H3
H4=$H4
EOF
        
    log "Generated obfuscation values:"
    log "  Jc=$Jc, Jmin=$Jmin, Jmax=$Jmax"
    log "  S1=$S1, S2=$S2"
    log "  H1=$H1, H2=$H2, H3=$H3, H4=$H4"
    log "WG_ENDPOINT set to: $WG_ENDPOINT"
    
    log "Created .env file in $SCRIPT_DIR"
}

prompt_user

setup_env
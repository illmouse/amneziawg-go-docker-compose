#!/bin/bash
set -e

# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/functions.sh"

WG_ENDPOINT=${WG_ENDPOINT:-}
WG_MODE=${WG_MODE:-server}
WG_PEER_COUNT=${WG_PEER_COUNT:-1}
SQUID_ENABLED=${SQUID_ENABLED:-true}
SQUID_PORT=${SQUID_PORT:-3128}
WG_PORT=${WG_PORT:-13440}
WG_IFACE=${WG_IFACE:-wg0}
WG_ADDRESS=${WG_ADDRESS:-10.100.0.1/24}

export WG_ENDPOINT
export WG_MODE
export WG_PEER_COUNT
export SQUID_ENABLED
export SQUID_PORT
export WG_PORT
export WG_IFACE
export WG_ADDRESS

setup_env() {
    log "Setting up environment..."
    
    local project_dir="$(dirname "$SCRIPT_DIR")"
    
    # Step 1: Handle .env file
    if [ ! -f "$project_dir/.env" ]; then
        log "Creating .env file with generated obfuscation values"
        
        # Set default values as fallback if variables aren't exported from setup.sh
        
        
        # Generate random values for obfuscation parameters
        Jc=$(get_random_int 3 10)
        Jmin=$(get_random_int 1 10)
        Jmax=$(get_random_int 50 1000)
        S1=$(get_random_junk_size)
        S2=$(get_random_junk_size)
        H1=$(get_random_header)
        H2=$(get_random_header)
        H3=$(get_random_header)
        H4=$(get_random_header)
        
        # Create .env file directly from template inside script with all values
        cat > "$project_dir/.env" << EOF
# .env
# Mandatory params

# Public endpoint
WG_ENDPOINT=$WG_ENDPOINT

# Optional default params

# Squid config
SQUID_ENABLED=$SQUID_ENABLED
SQUID_PORT=$SQUID_PORT

# Name of the VPN interface inside the container
WG_IFACE=$WG_IFACE
# Server IP and subnet
WG_ADDRESS=$WG_ADDRESS
# VPN port to accept connections
WG_PORT=$WG_PORT
# Number of peers to create
WG_PEER_COUNT=$WG_PEER_COUNT
# Client mode: Connects to peers using configs from config/peers/
WG_MODE=$WG_MODE

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
    else
        log ".env file already exists, using existing values"
    fi
    
    # Source the .env file to make variables available in this script
    # source "$project_dir/.env"
    
    # Ensure all required variables are set
    if [ -z "$WG_ENDPOINT" ]; then
        error "WG_ENDPOINT is not set in .env file"
        exit 1
    fi
    
    log "Environment setup complete"
}

fix_permissions "$SCRIPT_DIR"/scripts
fix_permissions "$SCRIPT_DIR"/entrypoint

prompt_user

setup_env
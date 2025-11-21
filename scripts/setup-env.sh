#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/functions.sh"

setup_env() {
    log "Setting up environment..."
    
    local project_dir="$(dirname "$SCRIPT_DIR")"
    
    # Step 1: Handle .env file
    if [ ! -f "$project_dir/.env" ]; then
        log "Creating .env file with generated obfuscation values"
        
        # Generate random values
        Jc=$(get_random_int 3 10)
        Jmin=$(get_random_int 1 10)
        Jmax=$(get_random_int 50 1000)
        S1=$(get_random_junk_size)
        S2=$(get_random_junk_size)
        H1=$(get_random_header)
        H2=$(get_random_header)
        H3=$(get_random_header)
        H4=$(get_random_header)
        
        if [ -f "$project_dir/.env.example" ]; then
            # Use env.example as template
            cp "$project_dir/.env.example" "$project_dir/.env"
            
            # Update the generated values in the new .env file using | as delimiter to avoid conflicts with / in values
            sed -i "s|^Jc=.*|Jc=$Jc|" "$project_dir/.env"
            sed -i "s|^Jmin=.*|Jmin=$Jmin|" "$project_dir/.env"
            sed -i "s|^Jmax=.*|Jmax=$Jmax|" "$project_dir/.env"
            sed -i "s|^S1=.*|S1=$S1|" "$project_dir/.env"
            sed -i "s|^S2=.*|S2=$S2|" "$project_dir/.env"
            sed -i "s|^H1=.*|H1=$H1|" "$project_dir/.env"
            sed -i "s|^H2=.*|H2=$H2|" "$project_dir/.env"
            sed -i "s|^H3=.*|H3=$H3|" "$project_dir/.env"
            sed -i "s|^H4=.*|H4=$H4|" "$project_dir/.env"
            
        else
            warn ".env.example not found, creating basic .env file with generated values"
            cat > "$project_dir/.env" << EOF
# .env
# Mandatory params

# Public endpoint
WG_ENDPOINT=

# Optional default params

# Squid config
SQUD_ENABLE=true
SQUID_PORT=3128

# Name of the VPN interface inside the container
WG_IFACE=wg0
# Server IP and subnet
WG_ADDRESS=10.100.0.1/24
# VPN port to accept connections
WG_PORT=13440
# Number of peers to create
WG_PEER_COUNT=1
# Client mode: Connects to peers using configs from config/peers/
WG_MODE=server

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
        fi
        
        log "Generated obfuscation values:"
        log "  Jc=$Jc, Jmin=$Jmin, Jmax=$Jmax"
        log "  S1=$S1, S2=$S2"
        log "  H1=$H1, H2=$H2, H3=$H3, H4=$H4"
    else
        log ".env file already exists, using existing values"
    fi
    
    # Check if WG_ENDPOINT is empty or not set
    if grep -q "WG_ENDPOINT=\"\"\|WG_ENDPOINT=''\|^WG_ENDPOINT=\$" "$project_dir/.env" || ! grep -q "^WG_ENDPOINT=" "$project_dir/.env"; then
        warn "WG_ENDPOINT is not set or empty in .env file"
        log "Detecting public IP address..."
        
        # Try to get public IP using ifconfig.me
        if PUBLIC_IP=$(curl -s -m 10 ifconfig.me); then
            log "Detected public IP: $PUBLIC_IP"
            user_endpoint="$PUBLIC_IP"
        else
            error "Failed to detect public IP automatically"
            echo "Please enter your server's public IP address or domain name:"
            read -r user_endpoint
        fi
        
        # Remove existing WG_ENDPOINT line if it exists
        grep -v "^WG_ENDPOINT=" "$project_dir/.env" > "$project_dir/.env.tmp" || true
        mv "$project_dir/.env.tmp" "$project_dir/.env"
        
        # Add the new WG_ENDPOINT
        echo "WG_ENDPOINT=$user_endpoint" >> "$project_dir/.env"
        log "WG_ENDPOINT has been set to: $user_endpoint"
    fi
    
    # Source the .env file to make variables available in this script
    source "$project_dir/.env"
    
    # Ensure all required variables are set
    if [ -z "$WG_ENDPOINT" ]; then
        error "WG_ENDPOINT is not set in .env file"
        exit 1
    fi
    
    # Set default values if not already set
    WG_PORT=${WG_PORT:-13440}
    WG_IFACE=${WG_IFACE:-wg0}
    WG_ADDRESS=${WG_ADDRESS:-10.100.0.1/24}
    WG_PEER_COUNT=${WG_PEER_COUNT:-1}
    WG_MODE=${WG_MODE:-server}
    SQUD_ENABLE=${SQUD_ENABLE:-true}
    SQUID_PORT=${SQUID_PORT:-3128}
    
    # Update .env with any defaults that were missing
    sed -i "s/^WG_PORT=.*/WG_PORT=$WG_PORT/" "$project_dir/.env"
    sed -i "s/^WG_IFACE=.*/WG_IFACE=$WG_IFACE/" "$project_dir/.env"
    sed -i "s/^WG_ADDRESS=.*/WG_ADDRESS=$WG_ADDRESS/" "$project_dir/.env"
    sed -i "s/^WG_PEER_COUNT=.*/WG_PEER_COUNT=$WG_PEER_COUNT/" "$project_dir/.env"
    sed -i "s/^WG_MODE=.*/WG_MODE=$WG_MODE/" "$project_dir/.env"
    sed -i "s/^SQUD_ENABLE=.*/SQUD_ENABLE=$SQUD_ENABLE/" "$project_dir/.env"
    sed -i "s/^SQUID_PORT=.*/SQUID_PORT=$SQUID_PORT/" "$project_dir/.env"
    
    log "Environment setup complete"
}

setup_env
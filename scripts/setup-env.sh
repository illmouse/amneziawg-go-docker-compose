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
        JC=$(get_random_int 3 10)
        JMIN=50
        JMAX=1000
        S1=$(get_random_junk_size)
        S2=$(get_random_junk_size)
        H1=$(get_random_header)
        H2=$(get_random_header)
        H3=$(get_random_header)
        H4=$(get_random_header)
        
        if [ -f "$project_dir/.env.example" ]; then
            # Use env.example as template and replace values in place
            cp "$project_dir/.env.example" "$project_dir/.env"
            
            # Update the generated values in the new .env file
            sed -i "s/^JC=.*/JC=$JC/" "$project_dir/.env"
            sed -i "s/^JMIN=.*/JMIN=$JMIN/" "$project_dir/.env"
            sed -i "s/^JMAX=.*/JMAX=$JMAX/" "$project_dir/.env"
            sed -i "s/^S1=.*/S1=$S1/" "$project_dir/.env"
            sed -i "s/^S2=.*/S2=$S2/" "$project_dir/.env"
            sed -i "s/^H1=.*/H1=$H1/" "$project_dir/.env"
            sed -i "s/^H2=.*/H2=$H2/" "$project_dir/.env"
            sed -i "s/^H3=.*/H3=$H3/" "$project_dir/.env"
            sed -i "s/^H4=.*/H4=$H4/" "$project_dir/.env"
            
        else
            warn ".env.example not found, creating basic .env file with generated values"
            cat > "$project_dir/.env" << EOF
WG_PORT=13440
WG_ENDPOINT=
JC=$JC
JMIN=$JMIN
JMAX=$JMAX
S1=$S1
S2=$S2
H1=$H1
H2=$H2
H3=$H3
H4=$H4
EOF
        fi
        
        log "Generated obfuscation values:"
        log "  JC=$JC, JMIN=$JMIN, JMAX=$JMAX"
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
    
    return 0
}

setup_env
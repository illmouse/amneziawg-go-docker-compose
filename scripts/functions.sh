#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[SETUP]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Random number generation functions
get_random_int() {
    local min=$1
    local max=$2
    # Use /dev/urandom for better random numbers and larger range
    echo $(( min + ( $(od -An -N4 -tu4 /dev/urandom) % (max - min + 1) ) ))
}

get_random_junk_size() {
    get_random_int 15 150
}

get_random_header() {
    get_random_int 1 2147483647
}

get_public_endpoint() {
    # Try to get public IP using ifconfig.me
    local endpoint=$(curl -s --connect-timeout 10 --max-time 10 https://ifconfig.me)
    
    if [ -z "$endpoint" ] || ! [[ "$endpoint" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # Try alternative method
        endpoint=$(curl -s --connect-timeout 10 --max-time 10 http://api.ipify.org)
    fi
    
    echo "$endpoint"
}

prompt_user() {
    log "Starting AmneziaWG setup..."
    
    # Set default values for SQUID_ENABLE and SQUID_PORT based on .env.example
    SQUD_ENABLE=${SQUD_ENABLE:-"true"}
    SQUID_PORT=${SQUID_PORT:-"3128"}
    
    # Interactive setup for WG_MODE
    echo ""
    log "Select AmneziaWG mode:"
    echo "1) Server mode (default) - Acts as a VPN server, accepts connections from clients"
    echo "2) Client mode - Connects to remote VPN servers using peer configurations"
    echo -n "Choose mode (1-2, default 1): "
    read -r mode_choice
    case "$mode_choice" in
        1|""|server|Server|SERVER)
            WG_MODE="server"
            log "Selected: Server mode"
            ;;
        2|client|Client|CLIENT)
            WG_MODE="client"
            log "Selected: Client mode"
            ;;
        *)
            log "Invalid choice, defaulting to Server mode"
            WG_MODE="server"
            ;;
    esac
    
    # Interactive setup for WG_PEER_COUNT (only for server mode)
    if [ "$WG_MODE" = "server" ]; then
        echo ""
        log "Configure number of peers to create:"
        echo "This determines how many client configurations will be generated"
        echo -n "Enter number of peers (1-10, default 1): "
        read -r peer_count
        if [[ "$peer_count" =~ ^[0-9]+$ ]] && [ "$peer_count" -ge 1 ] && [ "$peer_count" -le 10 ]; then
            WG_PEER_COUNT="$peer_count"
            log "Set WG_PEER_COUNT=$WG_PEER_COUNT"
        else
            WG_PEER_COUNT=1
            log "Invalid input, defaulting to WG_PEER_COUNT=1"
        fi
    fi
    
    # Interactive setup for SQUD_ENABLE and SQUID_PORT (only for client mode)
    if [ "$WG_MODE" = "client" ]; then
        echo ""
        log "Configure Squid proxy settings:"
        echo "Squid proxy can be enabled to route traffic through a proxy server"
        echo -n "Enable Squid proxy? (y/n, default y): "
        read -r squid_enable_choice
        case "$squid_enable_choice" in
            y|Y|yes|Yes|YES)
                SQUD_ENABLE="true"
                log "Enabled Squid proxy"
                ;;
            n|N|no|No|NO)
                SQUD_ENABLE="false"
                log "Disabled Squid proxy"
                ;;
            *)
                SQUD_ENABLE="true"
                log "No input provided, defaulting to enabled"
                ;;
        esac
        
        if [ "$SQUD_ENABLE" = "true" ]; then
            echo ""
            echo -n "Enter Squid port (default 3128): "
            read -r squid_port
            if [[ "$squid_port" =~ ^[0-9]+$ ]] && [ "$squid_port" -ge 1 ] && [ "$squid_port" -le 65535 ]; then
                SQUID_PORT="$squid_port"
                log "Set SQUID_PORT=$SQUID_PORT"
            else
                SQUID_PORT=3128
                log "Invalid input, defaulting to SQUID_PORT=3128"
            fi
        fi
    fi
    
    # Automatically determine public endpoint using ifconfig.me
    echo ""
    log "Determining public endpoint automatically..."
    
    # Get public endpoint using the dedicated function
    WG_ENDPOINT=$(get_public_endpoint)
    
    if [ -z "$WG_ENDPOINT" ] || ! [[ "$WG_ENDPOINT" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        warn "Could not determine public IP automatically. Please provide one manually."
        echo "This is the public IP or domain name that clients will use to connect to your server"
        echo "Example: 192.168.1.100 or yourdomain.com"
        echo -n "Enter public endpoint: "
        read -r wg_endpoint
        if [ -z "$wg_endpoint" ]; then
            error "WG_ENDPOINT is mandatory. Please provide a valid public IP or domain name."
            exit 1
        fi
        WG_ENDPOINT="$wg_endpoint"
    else
        log "Detected public endpoint: $WG_ENDPOINT"
    fi
}

fix_permissions() {
    local script_dir="$1"

    chmod +x "$script_dir"/scripts/*.sh "$script_dir"/entrypoint/*.sh
}

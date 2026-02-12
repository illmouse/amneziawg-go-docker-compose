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

get_random_range() {
  local min=$1
  local max=$2

  local a=$(( RANDOM * RANDOM % (max - min + 1) + min ))
  local b
  while true; do
    b=$(( RANDOM * RANDOM % (max - min + 1) + min ))
    (( b != a )) && break
  done

  if (( a < b )); then
    echo "${a}-${b}"
  else
    echo "${b}-${a}"
  fi
}

get_random_junk_size() {
    get_random_int 1 15
}

get_random_header() {
    get_random_int 1 2147483647
}

get_random_header_range() {
    get_random_range $1 $2
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
    
    # Set default values for PROXY
    PROXY_SOCKS5_ENABLED=${PROXY_SOCKS5_ENABLED:-"false"}
    PROXY_SOCKS5_PORT=${PROXY_SOCKS5_PORT:-"4128"}
    PROXY_HTTP_ENABLED=${PROXY_HTTP_ENABLED:-"false"}
    PROXY_HTTP_PORT=${PROXY_HTTP_PORT:-"3128"}
    
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
    
    # Interactive setup for PROXY (only for client mode)
    if [ "$WG_MODE" = "client" ]; then
        echo ""
        log "Configure proxy settings:"
        echo "Proxy can be enabled to route traffic through a proxy server"
        echo -n "Enable SOCKS5 proxy? (y/n, default y): "
        read -r proxy_enable_choice
        case "$proxy_enable_choice" in
            y|Y|yes|Yes|YES)
                PROXY_SOCKS5_ENABLED="true"
                log "Enabled proxy"
                ;;
            n|N|no|No|NO)
                PROXY_SOCKS5_ENABLED="false"
                log "Disabled proxy"
                ;;
            "")
                PROXY_SOCKS5_ENABLED="true"
                log "No input provided, defaulting to enabled"
                ;;
            *)
                PROXY_SOCKS5_ENABLED="true"
                log "Invalid choice, defaulting to enabled"
                ;;
        esac
        
        if [ "$PROXY_SOCKS5_ENABLED" = "true" ]; then
            echo ""
            echo -n "Enter proxy SOCKS5 port (default 4128): "
            read -r PROXY_SOCKS5_PORT
            if [[ "$PROXY_SOCKS5_PORT" =~ ^[0-9]+$ ]] && [ "$PROXY_SOCKS5_PORT" -ge 1 ] && [ "$PROXY_SOCKS5_PORT" -le 65535 ]; then
                PROXY_SOCKS5_PORT="$PROXY_SOCKS5_PORT"
                log "Set PROXY_SOCKS5_PORT=$PROXY_SOCKS5_PORT"
            else
                PROXY_SOCKS5_PORT=4128
                log "Invalid input, defaulting to PROXY_SOCKS5_PORT=4128"
            fi
        fi

        echo -n "Enable HTTP proxy? (y/n, default y): "
        read -r proxy_enable_choice
        case "$proxy_enable_choice" in
            y|Y|yes|Yes|YES)
                PROXY_HTTP_ENABLED="true"
                log "Enabled proxy"
                ;;
            n|N|no|No|NO)
                PROXY_HTTP_ENABLED="false"
                log "Disabled proxy"
                ;;
            "")
                PROXY_HTTP_ENABLED="true"
                log "No input provided, defaulting to enabled"
                ;;
            *)
                PROXY_HTTP_ENABLED="true"
                log "Invalid choice, defaulting to enabled"
                ;;
        esac
        
        if [ "$PROXY_HTTP_ENABLED" = "true" ]; then
            echo ""
            echo -n "Enter proxy HTTP port (default 3128): "
            read -r PROXY_HTTP_PORT
            if [[ "$PROXY_HTTP_PORT" =~ ^[0-9]+$ ]] && [ "$PROXY_HTTP_PORT" -ge 1 ] && [ "$PROXY_HTTP_PORT" -le 65535 ]; then
                PROXY_HTTP_PORT="$PROXY_HTTP_PORT"
                log "Set PROXY_HTTP_PORT=$PROXY_HTTP_PORT"
            else
                PROXY_HTTP_PORT=3128
                log "Invalid input, defaulting to PROXY_HTTP_PORT=3128"
            fi
        fi
    fi
}

fix_permissions() {
    local script_dir="$1"
    log "Fixing permissions for $script_dir/*.sh"
    chmod +x "$script_dir"/*.sh
}

start_services() {
    log "Starting services..."
    
    # Start Docker Compose
    log "Starting Docker Compose from current directory"
    cd "$SCRIPT_DIR" && docker compose up -d
    
    # Show status
    log "Checking container status..."
    docker ps --filter "name=amneziawg"
    
    return 0
}
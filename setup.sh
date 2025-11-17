#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
    echo -e "${GREEN}[SETUP]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "Please run as root or with sudo"
    exit 1
fi

main() {
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
    
    # Try to get public IP using ifconfig.me
    WG_ENDPOINT=$(curl -s --connect-timeout 10 --max-time 10 https://ifconfig.me)
    
    if [ -z "$WG_ENDPOINT" ] || ! [[ "$WG_ENDPOINT" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        warn "Could not determine public IP from ifconfig.me, trying alternative method..."
        WG_ENDPOINT=$(curl -s --connect-timeout 10 --max-time 10 http://api.ipify.org)
    fi
    
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
    
    # Create .env file with user selections
    log "Creating .env file with user configuration..."
    cat > .env << EOF
# .env
# Mandatory params

# Public endpoint
WG_ENDPOINT=$WG_ENDPOINT

# Optional default params

# Squid config
SQUD_ENABLE=$SQUD_ENABLE
SQUID_PORT=$SQUID_PORT

# Name of the VPN interface inside the container
WG_IFACE=wg0
# Server IP and subnet
WG_ADDRESS=10.100.0.1/24
# VPN port to accept connections
WG_PORT=13440
# Number of peers to create
WG_PEER_COUNT=$WG_PEER_COUNT
# Client mode: Connects to peers using configs from config/peers/
WG_MODE=$WG_MODE

# AmneziaWG tunable parameters
Jc=3
Jmin=1
Jmax=50
S1=25
S2=72
H1=1411927821
H2=1212681123
H3=1327217326
H4=1515483925
EOF
    
    chmod +x "$SCRIPT_DIR"/scripts/*.sh "$SCRIPT_DIR"/entrypoint/*.sh
    
    # Step 1: Install Docker and Docker Compose
    if ! "$SCRIPT_DIR/scripts/install-docker.sh"; then
        error "Docker installation failed"
        exit 1
    fi
    
    # Step 2: Configure system settings
    if ! "$SCRIPT_DIR/scripts/configure-system.sh"; then
        error "System configuration failed"
        exit 1
    fi
    
    # Step 3: Setup environment
    if ! "$SCRIPT_DIR/scripts/setup-env.sh"; then
        error "Environment setup failed"
        exit 1
    fi
    
    # Step 4: Start services
    if ! "$SCRIPT_DIR/scripts/start-services.sh"; then
        error "Service startup failed"
        exit 1
    fi
    
    log "Setup complete!"
    log "- IP forwarding configured in /etc/sysctl.conf"
    log "- Container logs: docker logs amneziawg"
    log "- .env file configured with WG_ENDPOINT and obfuscation values"
    if [ "$WG_MODE" = "client" ]; then
        log "- Tunnel monitoring enabled (client mode)"
    else
        log "- Tunnel monitoring disabled (server mode)"
    fi
}

main "$@"
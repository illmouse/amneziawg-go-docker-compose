#!/bin/sh

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Emojis
INFO_EMOJI="🔵"
SUCCESS_EMOJI="✅"
WARNING_EMOJI="⚠️ "
ERROR_EMOJI="❌"
CONFIG_EMOJI="⚙️ "
KEY_EMOJI="🔑"
NETWORK_EMOJI="🌐"
PEER_EMOJI="👤"
START_EMOJI="🚀"
SECURITY_EMOJI="🔒"
DNS_EMOJI="🌍"
SQUID_EMOJI="🦑"

# Log levels (in order of verbosity)
LOG_ERROR=0
LOG_WARN=1
LOG_INFO=2
LOG_DEBUG=3

# Default log level if not set
DEFAULT_LOG_LEVEL=$LOG_INFO

# Get current log level, default to INFO if not set
get_log_level() {
    case "${LOG_LEVEL:-}" in
        "ERROR") return $LOG_ERROR ;;
        "WARN")  return $LOG_WARN ;;
        "INFO")  return $LOG_INFO ;;
        "DEBUG") return $LOG_DEBUG ;;
        *)       return $DEFAULT_LOG_LEVEL ;;
    esac
}

# Check if we should log at the given level
should_log() {
    local level=$1
    get_log_level
    local current_level=$?
    [ $level -le $current_level ]
}

log() { 
    if should_log $LOG_INFO; then
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] ${INFO_EMOJI} $*" | tee -a "$WG_LOGFILE" 
    fi
}

success() { 
    if should_log $LOG_INFO; then
        echo -e "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] ${GREEN}${SUCCESS_EMOJI} $*${NC}" | tee -a "$WG_LOGFILE" 
    fi
}

warn() { 
    if should_log $LOG_WARN; then
        echo -e "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] ${YELLOW}${WARNING_EMOJI} $*${NC}" | tee -a "$WG_LOGFILE" 
    fi
}

error() { 
    if should_log $LOG_ERROR; then
        echo -e "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] ${RED}${ERROR_EMOJI} ERROR: $*${NC}" | tee -a "$WG_LOGFILE" 
    fi
}

info() { 
    if should_log $LOG_INFO; then
        echo -e "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] ${BLUE}${INFO_EMOJI} $*${NC}" | tee -a "$WG_LOGFILE" 
    fi
}

debug() { 
    if should_log $LOG_DEBUG; then
        echo -e "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] ${CYAN}${CONFIG_EMOJI} $*${NC}" | tee -a "$WG_LOGFILE" 
    fi
}

gen_key() { 
    awg genkey 2>/dev/null | tr -d '\n\r'
}

gen_psk() { 
    awg genpsk 2>/dev/null | tr -d '\n\r'
}

pub_from_priv() { 
    local priv_key="$1"
    echo "$priv_key" | awg pubkey 2>/dev/null | tr -d '\n\r'
}

get_peer_ip() {
    local base_ip="${WG_ADDRESS%/*}"
    local prefix="32"
    local octet4="${base_ip##*.}"
    local base_octets="${base_ip%.*}"
    local peer_num="$1"
    echo "${base_octets}.$((octet4 + peer_num))/${prefix}"
}

# Get a value from the JSON DB
get_db_value() {
    local jq_path="$1"
    jq -r "$jq_path // empty" "$CONFIG_DB"
}

# Set a value in the JSON DB
set_db_value() {
    local jq_path="$1"
    local value="$2"
    # Create temp file to safely update
    tmp=$(mktemp)
    jq "$jq_path = $value" "$CONFIG_DB" > "$tmp" && mv "$tmp" "$CONFIG_DB"
}

# Function to fix permissions
fix_permissions() {
    info "${SECURITY_EMOJI} Fixing permissions in $WG_DIR..."
    
    # Fix directory permissions
    find "$WG_DIR" -type d -exec chmod 700 {} \; 2>/dev/null || true
    success "Directory permissions set to 700"
    
    # Fix file permissions (config files and keys should be 600)
    find "$WG_DIR" -type f -name "*.conf" -exec chmod 600 {} \; 2>/dev/null || true
    find "$WG_DIR" -type f -name "*.json" -exec chmod 600 {} \; 2>/dev/null || true
    find "$WG_DIR" -type f -name "*.key" -exec chmod 600 {} \; 2>/dev/null || true
    find "$KEYS_DIR" -type f -exec chmod 600 {} \; 2>/dev/null || true
    find "$CLIENT_PEERS_DIR" -type f -exec chmod 600 {} \; 2>/dev/null || true
    find "$SERVER_PEERS_DIR" -type f -exec chmod 600 {} \; 2>/dev/null || true
    
    # Specific files
    [ -f "$CONFIG_DB" ] && chmod 600 "$CONFIG_DB"
    [ -f "$WG_DIR/$WG_CONF_FILE" ] && chmod 600 "$WG_DIR/$WG_CONF_FILE"
    
    success "File permissions set to 600"
}

# Function to configure DNS in container
configure_dns() {
    local dns_servers="$1"
    info "${DNS_EMOJI} Configuring DNS servers: $dns_servers"
    
    # Method 1: Update /etc/resolv.conf directly
    if [ -w "/etc/resolv.conf" ]; then
        # Backup original resolv.conf
        cp /etc/resolv.conf /etc/resolv.conf.backup 2>/dev/null || true
        
        # Create new resolv.conf with the specified DNS servers
        echo "# DNS configured by AmneziaWG client" > /etc/resolv.conf
        echo "# Original backup: /etc/resolv.conf.backup" >> /etc/resolv.conf
        
        # Add each DNS server
        echo "$dns_servers" | tr ',' '\n' | while read -r dns_server; do
            dns_server=$(echo "$dns_server" | tr -d ' ')
            if [ -n "$dns_server" ]; then
                echo "nameserver $dns_server" >> /etc/resolv.conf
            fi
        done
        
        # Add search domain if needed and other options
        echo "options rotate" >> /etc/resolv.conf
        echo "options timeout:1" >> /etc/resolv.conf
        
        success "DNS configured in /etc/resolv.conf"
        
    # Method 2: Use environment variables (for Docker)
    else
        warn "Cannot write to /etc/resolv.conf, using alternative methods"
        info "To use DNS in client mode, set these environment variables in your container:"
        
        echo "$dns_servers" | tr ',' '\n' | while read -r dns_server; do
            dns_server=$(echo "$dns_server" | tr -d ' ')
            if [ -n "$dns_server" ]; then
                info "  -e DNS_SERVER=$dns_server"
            fi
        done
    fi
    
    # Test DNS resolution
    if command -v nslookup >/dev/null 2>&1; then
        info "Testing DNS resolution..."
        if nslookup google.com >/dev/null 2>&1; then
            success "DNS resolution working"
        else
            warn "DNS resolution test failed"
        fi
    fi
}

# Function to setup Squid proxy
setup_squid() {
    info "${SQUID_EMOJI} Setting up Squid proxy..."
    
    # Install Squid
    if ! command -v squid >/dev/null 2>&1; then
        info "Installing Squid..."
        if ! apk add --no-cache squid; then
            error "Failed to install Squid"
        fi
        success "Squid installed successfully"
    else
        info "Squid already installed"
    fi
    
    # Create Squid configuration directories
    SQUID_CONF_DIR="/etc/squid"
    SQUID_CACHE_DIR="/var/cache/squid"
    SQUID_LOG_DIR="/var/log/amneziawg/squid"
    
    mkdir -p "$SQUID_CONF_DIR" "$SQUID_CACHE_DIR" "$SQUID_LOG_DIR"
    
    # Fix permissions
    chown -R squid:squid "$SQUID_CACHE_DIR" "$SQUID_LOG_DIR" 2>/dev/null || true
    chmod 755 "$SQUID_CACHE_DIR" "$SQUID_LOG_DIR"
    
    # Simple Squid config using SQUID_PORT variable
    cat > "$SQUID_CONF_DIR/squid.conf" << SQUID_CONFIG
# Squid proxy configuration
http_port 0.0.0.0:${SQUID_PORT}

# Allow all traffic
http_access allow all

# Cache settings for mixed file sizes
cache_dir ufs /var/cache/squid 5000 16 256
cache_mem 512 MB
maximum_object_size 20 GB

# Performance settings
via on
forwarded_for delete
pipeline_prefetch 2
connect_timeout 45 seconds
read_timeout 1800 seconds
SQUID_CONFIG
    
    # Initialize Squid cache
    info "Initializing Squid cache..."
    if squid -z -N -f /etc/squid/squid.conf; then
        success "Squid cache initialized"
    else
        warn "Squid cache initialization had issues"
    fi
    
    success "Squid proxy configuration created for port ${SQUID_PORT}"
}

# Function to start Squid proxy
start_squid() {
    if [ "$SQUID_ENABLE" != "true" ]; then
        info "${SQUID_EMOJI} Squid proxy is disabled, skipping..."
        return
    fi

    info "${SQUID_EMOJI} Starting Squid proxy..."
    
    # Kill any existing Squid processes first
    pkill squid 2>/dev/null || true
    sleep 2
    
    # Start Squid in foreground and background it
    info "Starting Squid process on port ${SQUID_PORT}..."
    squid -f /etc/squid/squid.conf -N &
    SQUID_PID=$!
    
    # Wait for Squid to start
    sleep 3
    
    if kill -0 $SQUID_PID 2>/dev/null; then
        success "Squid proxy running on port ${SQUID_PORT} (PID: $SQUID_PID)"
        
        # Check if it's listening
        if netstat -tuln | grep -q ":${SQUID_PORT} "; then
            success "Squid is listening on port ${SQUID_PORT}"
            
            # Show listening addresses
            info "Squid listening addresses:"
            netstat -tuln | grep ":${SQUID_PORT}" | while read -r line; do
                info "  $line"
            done
        else
            error "Squid is not listening on port ${SQUID_PORT}"
        fi
    else
        error "Squid failed to start on port ${SQUID_PORT}"
    fi
}


setup_wireguard_routing() {
    if [ "$WG_MODE" = "client" ]; then
        info "🌐 Setting up routing for WireGuard tunnel..."
        
        # Get the current default gateway and interface
        DEFAULT_GW=$(ip route | awk '/default/ {print $3; exit}')
        DEFAULT_IFACE=$(ip route | awk '/default/ {print $5; exit}')
        
        # Get WireGuard server endpoint IP
        WG_SERVER_IP=$(grep -E '^Endpoint' "$WG_DIR/$WG_CONF_FILE" | head -1 | awk -F'=' '{print $2}' | awk -F':' '{print $1}' | tr -d ' ')
        
        info "WireGuard server IP: $WG_SERVER_IP"
        
        # Step 1: Route WireGuard server through original gateway
        ip route add $WG_SERVER_IP via $DEFAULT_GW dev $DEFAULT_IFACE
        
        # Step 2: Change default route to WireGuard
        ip route del default
        ip route add default dev $WG_IFACE
        
        # Step 3: Add specific route for Docker network and local clients
        # ip route add 172.16.0.0/12 via $DEFAULT_GW dev $DEFAULT_IFACE
        # ip route add 10.0.0.0/8 via $DEFAULT_GW dev $DEFAULT_IFACE
        # ip route add 192.168.0.0/16 via $DEFAULT_GW dev $DEFAULT_IFACE
        
        info "Simple routing configured:"
        info "- Internet traffic → WireGuard"
        info "- Local/Docker traffic → Original interface"
        
        # Test
        if ping -c 2 -W 2 8.8.8.8 >/dev/null 2>&1; then
            success "WireGuard connectivity test passed"
        else
            error "WireGuard connectivity test failed. Tunnel may be unhealthy."
        fi
    fi
}

# ===============================
# WireGuard helper
# ===============================
start_wg_iface() {
    local iface="$1"

    info "Starting amneziawg-go on $iface..."
    amneziawg-go "$iface" >>"$WG_LOGFILE" 2>&1 &
    sleep 2

    info "Verifying WireGuard configuration..."
    if awg show "$iface" >>"$WG_LOGFILE" 2>&1; then
        success "WireGuard configuration verified"
    else
        warn "Could not verify configuration with 'awg show'"
    fi
}

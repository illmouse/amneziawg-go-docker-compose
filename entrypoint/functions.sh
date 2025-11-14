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

log() { 
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] ${INFO_EMOJI} $*" | tee -a "$WG_LOGFILE" 
}

success() { 
    echo -e "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] ${GREEN}${SUCCESS_EMOJI} $*${NC}" | tee -a "$WG_LOGFILE" 
}

warn() { 
    echo -e "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] ${YELLOW}${WARNING_EMOJI} $*${NC}" | tee -a "$WG_LOGFILE" 
}

error() { 
    echo -e "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] ${RED}${ERROR_EMOJI} ERROR: $*${NC}" | tee -a "$WG_LOGFILE" 
    exit 1
}

info() { 
    echo -e "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] ${BLUE}${INFO_EMOJI} $*${NC}" | tee -a "$WG_LOGFILE" 
}

debug() { 
    echo -e "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] ${CYAN}${CONFIG_EMOJI} $*${NC}" | tee -a "$WG_LOGFILE" 
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
    local prefix="${WG_ADDRESS#*/}"
    local octet4="${base_ip##*.}"
    local base_octets="${base_ip%.*}"
    local peer_num="$1"
    echo "${base_octets}.$((octet4 + peer_num))/${prefix}"
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
    find "$PEERS_DIR" -type f -exec chmod 600 {} \; 2>/dev/null || true
    
    # Specific files
    [ -f "$CONFIG_DB" ] && chmod 600 "$CONFIG_DB"
    [ -f "$WG_DIR/$WG_CONF_FILE" ] && chmod 600 "$WG_DIR/$WG_CONF_FILE"
    
    success "File permissions set to 600"
    
    # Log the permission changes
    info "Current permissions in $WG_DIR:"
    ls -la "$WG_DIR" | head -10 | while read line; do
        info "  $line"
    done
}
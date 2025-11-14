#!/bin/sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { 
    echo -e "${GREEN}[$(date -u +'%Y-%m-%dT%H:%M:%SZ')]${NC} $*" | tee -a "$WG_LOGFILE" 
}

warn() { 
    echo -e "${YELLOW}[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] WARN${NC} $*" | tee -a "$WG_LOGFILE" 
}

error() { 
    echo -e "${RED}[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] ERROR${NC} $*" | tee -a "$WG_LOGFILE" 
}

# Helper functions
gen_key()  { awg genkey 2>/dev/null | tr -d '\n\r'; }
gen_psk()  { awg genpsk 2>/dev/null | tr -d '\n\r'; }
pub_from_priv() { echo "$1" | awg pubkey 2>/dev/null | tr -d '\n\r'; }

# Function to calculate peer IP
get_peer_ip() {
    local base_ip="${WG_ADDRESS%/*}"
    local prefix="${WG_ADDRESS#*/}"
    local octet4="${base_ip##*.}"
    local base_octets="${base_ip%.*}"
    local peer_num="$1"
    
    echo "${base_octets}.$((octet4 + peer_num))/${prefix}"
}
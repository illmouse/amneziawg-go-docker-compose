#!/bin/sh

log() { 
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*" | tee -a "$WG_LOGFILE" 
}

error() { 
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] ERROR: $*" | tee -a "$WG_LOGFILE" 
    exit 1
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
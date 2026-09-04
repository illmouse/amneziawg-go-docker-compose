#!/bin/bash
set -e

# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/functions.sh"

setup_env() {
    log "Creating .env file..."
    

    log "Creating .env file with generated obfuscation values"
    
    # Set default values as fallback if variables aren't exported from setup.sh
    
    
    # Generate random values for obfuscation parameters
    Jc=$(get_random_int 3 10)
    Jmin=5
    Jmax=50
    S1=$(get_random_junk_size)
    S2=$(get_random_junk_size)
    S3=$(get_random_junk_size)
    S4=$(get_random_junk_size)
    H1=$(get_random_header_range 1 10000)
    H2=$(get_random_header_range 20000 30000)
    H3=$(get_random_header_range 40000 50000)
    H4=$(get_random_header_range 60000 70000)

    # AmneziaWG 3.1 profile (opt-in): Header Protection + content padding +
    # randomized timings + random trailers. S prefixes must be >= 12 bytes
    # (they carry the header-protection nonce); H1-H4 fall back to standard
    # compatibility values (1/2/3/4) since headers are cipher-protected.
    AWG31_ENABLED=${AWG31_ENABLED:-"false"}
    HeaderProtectionKey=""
    ContentPaddingAddition=""
    RekeyAfterTime=""
    RekeyTimeout=""
    RejectAfterTime=""
    KeepaliveTimeout=""
    MaxHandshakeAttempts=""
    RandomTrailers=""
    DisableCookies=""
    if [ "$AWG31_ENABLED" = "true" ]; then
        S1=$(get_random_junk_size_31)
        S2=$(get_random_junk_size_31)
        S3=$(get_random_junk_size_31)
        S4=$(get_random_junk_size_31)
        H1=1
        H2=2
        H3=3
        H4=4
        HeaderProtectionKey=$(generate_header_protection_key)
        ContentPaddingAddition=$(get_random_range 16 64)
        RekeyAfterTime=$(get_random_range 3000 4000)
        RekeyTimeout=$(get_random_range 5 10)
        RejectAfterTime=$(get_random_range 180 190)
        KeepaliveTimeout=$(get_random_range 8 15)
        MaxHandshakeAttempts=$(get_random_int 10 20)
        RandomTrailers="on"
    fi
    
    # Create .env file directly from template inside script with all values
    cat > "$SCRIPT_DIR/.env" << EOF
# .env
# Mandatory params

# Public endpoint
WG_ENDPOINT=$(get_public_endpoint)

# Optional default params

# Proxy config
PROXY_SOCKS5_ENABLED=$PROXY_SOCKS5_ENABLED
PROXY_SOCKS5_PORT=$PROXY_SOCKS5_PORT
PROXY_SOCKS5_AUTH_ENABLED=$PROXY_SOCKS5_AUTH_ENABLED

PROXY_HTTP_ENABLED=$PROXY_HTTP_ENABLED
PROXY_HTTP_PORT=$PROXY_HTTP_PORT
PROXY_HTTP_AUTH_ENABLED=$PROXY_HTTP_AUTH_ENABLED

PROXY_CUSTOM_CONFIG=$PROXY_CUSTOM_CONFIG

# Prometheus metrics
METRICS_ENABLED=$METRICS_ENABLED
METRICS_PORT=$METRICS_PORT
METRICS_INTERVAL=$METRICS_INTERVAL

# Name of the VPN interface inside the container
WG_IFACE=$WG_IFACE
# Server IP and subnet
WG_ADDRESS=$WG_ADDRESS
# VPN port to accept connections
WG_PORT=$WG_PORT
# Number of peers to create
WG_PEER_COUNT=$WG_PEER_COUNT
# Client mode: Connects to peers using configs from config/client_peers/
WG_MODE=$WG_MODE
# Master peer - peer config filename that will be main peer
# if set - once become available tunnel will always be switched to this peer
MASTER_PEER=
# log level to use - ERROR,INFO,WARN,DEBUG
LOG_LEVEL=INFO
# UDP protocol to be used for obfuscation. Available options: SIP, DNS, QUIC, STUN-WEBRTC
UDP_SIGNATURE=QUIC

# AmneziaWG tunable parameters
Jc=$Jc
Jmin=$Jmin
Jmax=$Jmax
S1=$S1
S2=$S2
S3=$S3
S4=$S4
H1=$H1
H2=$H2
H3=$H3
H4=$H4

# AmneziaWG 3.1 parameters (empty = disabled, standard 2.x behavior)
# HeaderProtectionKey: base64 32-byte key, requires S1-S4 >= 12
HeaderProtectionKey=$HeaderProtectionKey
# ContentPaddingAddition: random bytes added to payload (e.g. 16-64)
ContentPaddingAddition=$ContentPaddingAddition
# RekeyAfterTime: seconds before re-handshake (e.g. 3000-4000)
RekeyAfterTime=$RekeyAfterTime
# RekeyTimeout: handshake timeout in seconds (e.g. 5-10)
RekeyTimeout=$RekeyTimeout
# RejectAfterTime: seconds after which a new handshake is forced
RejectAfterTime=$RejectAfterTime
# KeepaliveTimeout: keepalive interval in seconds (e.g. 8-15)
KeepaliveTimeout=$KeepaliveTimeout
# MaxHandshakeAttempts: max handshake retries
MaxHandshakeAttempts=$MaxHandshakeAttempts
# RandomTrailers: on/off - random trailing bytes on packets
RandomTrailers=$RandomTrailers
# DisableCookies: on/off - suppress Cookie Reply packets
DisableCookies=$DisableCookies
EOF
        
    log "Generated obfuscation values:"
    log "  Jc=$Jc, Jmin=$Jmin, Jmax=$Jmax"
    log "  S1=$S1, S2=$S2, S3=$S3, S4=$S4"
    log "  H1=$H1, H2=$H2, H3=$H3, H4=$H4"
    if [ "$AWG31_ENABLED" = "true" ]; then
        log "  AmneziaWG 3.1 profile enabled:"
        log "    HeaderProtectionKey=$HeaderProtectionKey"
        log "    ContentPaddingAddition=$ContentPaddingAddition"
        log "    RekeyAfterTime=$RekeyAfterTime RekeyTimeout=$RekeyTimeout"
        log "    RejectAfterTime=$RejectAfterTime KeepaliveTimeout=$KeepaliveTimeout"
        log "    MaxHandshakeAttempts=$MaxHandshakeAttempts RandomTrailers=$RandomTrailers"
    fi
    log "WG_ENDPOINT set to: $WG_ENDPOINT"
    
    log "Created .env file in $SCRIPT_DIR"
}

prompt_user

setup_env
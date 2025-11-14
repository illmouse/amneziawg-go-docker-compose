#!/bin/sh
set -eu

# First set the critical environment variables needed for logging
: "${WG_LOGFILE:=/var/log/amneziawg/amneziawg.log}"
: "${WG_DIR:=/etc/amneziawg}"

# Create log directory first
mkdir -p "$(dirname "$WG_LOGFILE")"

# Simple log function that doesn't depend on other variables
log() { 
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*" | tee -a "$WG_LOGFILE" 
}

error() {
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] ERROR: $*" | tee -a "$WG_LOGFILE"
    exit 1
}

log "Initializing container environment..."

# Now set the rest of the environment variables
: "${TMP_DIR:=/tmp/amneziawg}"
: "${KEYS_DIR:=$WG_DIR/keys}"
: "${PEERS_DIR:=$WG_DIR/peers}"
: "${CONFIG_DB:=$WG_DIR/config.json}"
: "${WG_CONF_FILE:=wg0.conf}"

: "${WG_IFACE:=wg0}"
: "${WG_ADDRESS:=10.100.0.1/24}"
: "${WG_PORT:=13440}"
: "${WG_ENDPOINT:=}"
: "${WG_PEER_COUNT:=1}"

: "${Jc:=3}"
: "${Jmin:=1}"
: "${Jmax:=50}"
: "${S1:=25}"
: "${S2:=72}"
: "${H1:=1411927821}"
: "${H2:=1212681123}"
: "${H3:=1327217326}"
: "${H4:=1515483925}"

# Export all variables so they're available to other scripts
export WG_DIR TMP_DIR KEYS_DIR PEERS_DIR CONFIG_DB WG_CONF_FILE WG_LOGFILE
export WG_IFACE WG_ADDRESS WG_PORT WG_ENDPOINT WG_PEER_COUNT
export Jc Jmin Jmax S1 S2 H1 H2 H3 H4

# Install jq for JSON manipulation
if ! command -v jq >/dev/null 2>&1; then
    log "Installing jq..."
    apk add --no-cache jq >/dev/null 2>&1
fi

# Check if awg command is available
if ! command -v awg >/dev/null 2>&1; then
    error "awg command not found. Make sure amneziawg-go is properly installed."
fi

# Create directories
mkdir -p "$WG_DIR" "$TMP_DIR" "$KEYS_DIR" "$PEERS_DIR"

log "Environment initialized with:"
log "  WG_IFACE=$WG_IFACE, WG_ADDRESS=$WG_ADDRESS, WG_PORT=$WG_PORT"
log "  WG_PEER_COUNT=$WG_PEER_COUNT, WG_ENDPOINT=$WG_ENDPOINT"
log "  Jc=$Jc, Jmin=$Jmin, Jmax=$Jmax"
log "  S1=$S1, S2=$S2"
log "  H1=$H1, H2=$H2, H3=$H3, H4=$H4"
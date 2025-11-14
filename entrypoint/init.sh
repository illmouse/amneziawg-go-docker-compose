#!/bin/sh
set -eu

# Source functions
. /entrypoint/functions.sh

log "Initializing container environment..."

# Install jq for JSON manipulation
if ! command -v jq >/dev/null 2>&1; then
    log "Installing jq..."
    apk add --no-cache jq >/dev/null 2>&1
fi

# Create directories
mkdir -p "$WG_DIR" "$TMP_DIR" "$KEYS_DIR" "$PEERS_DIR"

# Set default environment variables
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

export WG_IFACE WG_ADDRESS WG_PORT WG_ENDPOINT WG_PEER_COUNT
export Jc Jmin Jmax S1 S2 H1 H2 H3 H4

log "Environment initialized"
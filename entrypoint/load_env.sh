#!/bin/bash
set -eu

# ===============================
# Load .env if exists
# ===============================
ENV_FILE="/etc/amneziawg/.env"
if [ -f "$ENV_FILE" ]; then
    set -o allexport
    . "$ENV_FILE"
    set +o allexport
fi

# ===============================
# Environment defaults
# ===============================

# Logging and directories
: "${WG_LOGFILE:=/var/log/amneziawg/amneziawg.log}"
: "${WG_DIR:=/etc/amneziawg}"
: "${TMP_DIR:=/tmp/amneziawg}"
: "${CLIENT_PEERS_DIR:=$WG_DIR/client_peers}"
: "${SERVER_PEERS_DIR:=$WG_DIR/server_peers}"
: "${CONFIG_DB:=$WG_DIR/config.json}"
: "${WG_CONF_FILE:=wg0.conf}"
: "${KEYS_DIR:=$WG_DIR/keys}"
: "${LOG_LEVEL:=INFO}"

# WireGuard defaults
: "${WG_IFACE:=wg0}"
: "${WG_ADDRESS:=10.100.0.1/24}"
: "${WG_PORT:=13440}"
: "${WG_ENDPOINT:=}"
: "${WG_PEER_COUNT:=1}"

# Squid defaults
: "${SQUID_ENABLE:=true}"
: "${SQUID_PORT:=3128}"
: "${SQUID_CACHE:=/var/cache/squid}"
: "${SQUID_LOG:=/var/log/amneziawg/squid/access.log}"
: "${SQUID_EMOJI:=🦑}"

# Junk/obfuscation values
: "${Jc:=3}"
: "${Jmin:=1}"
: "${Jmax:=50}"
: "${S1:=25}"
: "${S2:=72}"
: "${H1:=1411927821}"
: "${H2:=1212681123}"
: "${H3:=1327217326}"
: "${H4:=1515483925}"


# Export all variables for other scripts
export WG_DIR TMP_DIR CLIENT_PEERS_DIR SERVER_PEERS_DIR CONFIG_DB WG_CONF_FILE WG_LOGFILE KEYS_DIR LOG_LEVEL
export WG_IFACE WG_ADDRESS WG_PORT WG_ENDPOINT WG_PEER_COUNT
export SQUID_ENABLE SQUID_PORT SQUID_CACHE SQUID_LOG SQUID_EMOJI
export Jc Jmin Jmax S1 S2 H1 H2 H3 H4

#!/bin/bash

# ===============================
# Colors and emojis
# ===============================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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

# ===============================
# Logging
# ===============================
LOG_ERROR=0
LOG_WARN=1
LOG_INFO=2
LOG_DEBUG=3

DEFAULT_LOG_LEVEL=$LOG_INFO

get_log_level() {
    case "${LOG_LEVEL:-}" in
        "ERROR") return $LOG_ERROR ;;
        "WARN")  return $LOG_WARN ;;
        "INFO")  return $LOG_INFO ;;
        "DEBUG") return $LOG_DEBUG ;;
        *)       return $DEFAULT_LOG_LEVEL ;;
    esac
}

should_log() {
    local level=$1
    get_log_level
    local current_level=$?
    [ $level -le $current_level ]
}

log_message() {
    local level=$1
    local color=$2
    local emoji=$3
    shift 3
    local msg="$*"

    if should_log $level; then
        local timestamp="[$(date -u +'%Y-%m-%dT%H:%M:%SZ')]"
        echo -e "${timestamp} ${color}${emoji} ${msg}${NC}"
        echo "${timestamp} ${emoji} ${msg}" >> "$WG_LOGFILE"
    fi
}

info()    { log_message $LOG_INFO  "$BLUE"  "$INFO_EMOJI"    "INFO $*"; }
success() { log_message $LOG_INFO  "$GREEN" "$SUCCESS_EMOJI" "INFO $*"; }
warn()    { log_message $LOG_WARN  "$YELLOW" "$WARNING_EMOJI" "WARN $*"; }
error()   { log_message $LOG_ERROR "$RED"   "$ERROR_EMOJI"   "ERROR $*"; }
debug()   { log_message $LOG_DEBUG "$CYAN"  "$CONFIG_EMOJI"  "DEBUG $*"; }

# ===============================
# Cryptography
# ===============================
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

# ===============================
# IP helpers
# ===============================
get_peer_ip() {
    local base_ip="${WG_ADDRESS%/*}"
    local prefix="32"
    local octet4="${base_ip##*.}"
    local base_octets="${base_ip%.*}"
    local peer_num="$1"
    echo "${base_octets}.$((octet4 + peer_num))/${prefix}"
}

get_iface_ip() {
    local iface="$1"
    ip addr show "$iface" 2>/dev/null | grep "inet " | head -1 | awk '{print $2}' | cut -d/ -f1
}

# ===============================
# JSON database helpers
# ===============================
get_db_value() {
    local jq_path="$1"
    jq -r "$jq_path // empty" "$CONFIG_DB"
}

set_db_value() {
    local jq_path="$1"
    local value="$2"
    tmp=$(mktemp)
    jq "$jq_path = $value" "$CONFIG_DB" > "$tmp" && mv "$tmp" "$CONFIG_DB"
}

# ===============================
# Protocol obfuscation
# ===============================
generate_cps_value() {
    local RANDOM_LEN=64
    local COUNTER_FILE="$WG_DIR/cps_counter.state"
    local MAX_COUNTER=$((0xFFFFFFFF))

    if [[ ! -f "$COUNTER_FILE" ]]; then
        echo 1 > "$COUNTER_FILE"
    fi

    local COUNTER
    COUNTER=$(cat "$COUNTER_FILE")

    u32be() {
        printf "%08x" "$1"
    }

    local c t r

    if (( COUNTER > MAX_COUNTER )); then
        COUNTER=1
    fi

    c=$(u32be "$COUNTER")
    COUNTER=$((COUNTER + 1))
    echo "$COUNTER" > "$COUNTER_FILE"

    t=$(u32be "$(date +%s)")
    r=$(openssl rand -hex "$RANDOM_LEN")

    echo "<b 0x${c}${t}${r}>"
}

get_protocol_value() {
    debug "Setting CSP protocol for peer" >&2
    local code="$UDP_SIGNATURE"
    local default_value="${PROTOCOL_MAP[DEFAULT]}"
    local value

    if [[ -z "$code" ]]; then
        value="$default_value"
        debug "No protocol code provided. Using default: $value" >&2
    else
        if [[ -n "${PROTOCOL_MAP[$code]}" ]]; then
            value="${PROTOCOL_MAP[$code]}"
            debug "Found protocol '$code'" >&2
        else
            value="$default_value"
            warn "Protocol code '$code' not found. Using default." >&2
        fi
    fi

    echo "$value"
}

# ===============================
# File and directory helpers
# ===============================
ensure_directories() {
    mkdir -p "$WG_DIR" "$TMP_DIR" "$CLIENT_PEERS_DIR" "$SERVER_PEERS_DIR"
}

fix_permissions() {
    debug "${SECURITY_EMOJI} Fixing permissions in $WG_DIR..."

    find "$WG_DIR" -type d -exec chmod 700 {} \; 2>/dev/null || true
    debug "Directory permissions set to 700"

    find "$WG_DIR" -type f -name "*.conf" -exec chmod 600 {} \; 2>/dev/null || true
    find "$WG_DIR" -type f -name "*.json" -exec chmod 600 {} \; 2>/dev/null || true
    find "$WG_DIR" -type f -name "*.key" -exec chmod 600 {} \; 2>/dev/null || true
    find "$KEYS_DIR" -type f -exec chmod 600 {} \; 2>/dev/null || true
    find "$CLIENT_PEERS_DIR" -type f -exec chmod 600 {} \; 2>/dev/null || true
    find "$SERVER_PEERS_DIR" -type f -exec chmod 600 {} \; 2>/dev/null || true

    [ -f "$CONFIG_DB" ] && chmod 600 "$CONFIG_DB"
    [ -f "$WG_DIR/$WG_CONF_FILE" ] && chmod 600 "$WG_DIR/$WG_CONF_FILE"

    debug "File permissions set to 600"
}

# ===============================
# DNS configuration
# ===============================
configure_dns() {
    local dns_servers="$1"
    debug "${DNS_EMOJI} Configuring DNS servers: $dns_servers"

    if [ -w "/etc/resolv.conf" ]; then
        cp /etc/resolv.conf /etc/resolv.conf.backup 2>/dev/null || true

        echo "# DNS configured by AmneziaWG client" > /etc/resolv.conf
        echo "# Original backup: /etc/resolv.conf.backup" >> /etc/resolv.conf

        echo "$dns_servers" | tr ',' '\n' | while read -r dns_server; do
            dns_server=$(echo "$dns_server" | tr -d ' ')
            if [ -n "$dns_server" ]; then
                echo "nameserver $dns_server" >> /etc/resolv.conf
            fi
        done

        echo "options rotate" >> /etc/resolv.conf
        echo "options timeout:1" >> /etc/resolv.conf

        success "DNS configured in /etc/resolv.conf"
    else
        warn "Cannot write to /etc/resolv.conf, using alternative methods"
        debug "To use DNS in client mode, set these environment variables in your container:"

        echo "$dns_servers" | tr ',' '\n' | while read -r dns_server; do
            dns_server=$(echo "$dns_server" | tr -d ' ')
            if [ -n "$dns_server" ]; then
                debug "  -e DNS_SERVER=$dns_server"
            fi
        done
    fi

    if command -v nslookup >/dev/null 2>&1; then
        debug "Testing DNS resolution..."
        if nslookup google.com >/dev/null 2>&1; then
            success "DNS resolution working"
        else
            warn "DNS resolution test failed"
        fi
    fi
}

# ===============================
# Client routing
# ===============================
setup_client_routing() {
    if [ "$WG_MODE" = "client" ]; then
        debug "Setting up routing for WireGuard tunnel..."

        DEFAULT_GW=$(ip route | awk '/default/ {print $3; exit}')
        DEFAULT_IFACE=$(ip route | awk '/default/ {print $5; exit}')

        # Add routes for all peer endpoints via physical gateway
        # so WG traffic and health checks never go through the tunnel
        local peer_configs
        peer_configs=$(find "$CLIENT_PEERS_DIR" -name "*.conf" -type f 2>/dev/null)
        if [ -n "$peer_configs" ]; then
            while IFS= read -r peer_file; do
                local endpoint_host
                endpoint_host=$(conf_get_value "Endpoint" "$peer_file" | cut -d: -f1)
                if [ -n "$endpoint_host" ]; then
                    debug "Adding endpoint route: $endpoint_host via $DEFAULT_GW dev $DEFAULT_IFACE"
                    ip route add "$endpoint_host" via "$DEFAULT_GW" dev "$DEFAULT_IFACE" 2>/dev/null || true
                fi
            done <<< "$peer_configs"
        fi

        ip route del default
        ip route add default dev $WG_IFACE

        ip route add 172.16.0.0/12 via $DEFAULT_GW dev $DEFAULT_IFACE
        ip route add 10.0.0.0/8 via $DEFAULT_GW dev $DEFAULT_IFACE
        ip route add 192.168.0.0/16 via $DEFAULT_GW dev $DEFAULT_IFACE
        ip route add 100.64.0.0/10 via $DEFAULT_GW dev $DEFAULT_IFACE

        debug "Simple routing configured:"
        debug "- Internet traffic -> WireGuard"
        debug "- Local/Docker traffic -> Original interface"
        debug "- All peer endpoints -> Physical interface"

        if ping -c 2 -W 2 8.8.8.8 >/dev/null 2>&1; then
            success "WireGuard connectivity test passed"
        else
            error "WireGuard connectivity test failed. Tunnel may be unhealthy."
        fi
    fi
}

# ===============================
# WireGuard interface helpers
# ===============================
start_wg_iface() {
    local iface="$1"

    debug "Starting amneziawg-go on $iface..."
    amneziawg-go "$iface" >>"$WG_LOGFILE" 2>&1 &
    sleep 2

    debug "Verifying WireGuard configuration..."
    if awg show "$iface" >>"$WG_LOGFILE" 2>&1; then
        success "WireGuard configuration verified"
    else
        warn "Could not verify configuration with 'awg show'"
    fi
}

is_wg_interface_up() {
    if ! ip link show "$WG_IFACE" >/dev/null 2>&1; then
        error "WireGuard interface $WG_IFACE is down"
        return 1
    fi
    return 0
}

has_valid_wg_config() {
    local config_file="$1"
    if [ ! -f "$config_file" ]; then
        error "No WireGuard configuration found at $config_file"
        return 1
    fi
    return 0
}

is_wg_listening() {
    if ! awg show "$WG_IFACE" 2>/dev/null | grep -q "listening"; then
        error "WireGuard is not listening on $WG_IFACE"
        return 1
    fi
    return 0
}

# ===============================
# Environment validation
# ===============================
validate_environment() {
    local missing=0

    for cmd in awg amneziawg-go jq ip iptables; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error "Required command not found: $cmd"
            missing=$((missing + 1))
        fi
    done

    if [ "$WG_MODE" != "server" ] && [ "$WG_MODE" != "client" ]; then
        error "Invalid WG_MODE: $WG_MODE. Must be 'server' or 'client'"
        missing=$((missing + 1))
    fi

    if [ "$WG_MODE" = "server" ] && [ -z "$WG_ENDPOINT" ]; then
        warn "WG_ENDPOINT is not set -- clients won't know where to connect"
    fi

    if [ "$missing" -gt 0 ]; then
        error "Environment validation failed with $missing error(s)"
        return 1
    fi

    success "Environment validation passed"
    return 0
}

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
    debug "Setting CSP protocol for peer: $UDP_SIGNATURE" >&2
    if [[ -n "${PROTOCOL_MAP[$UDP_SIGNATURE]+_}" ]]; then
        debug "Using UDP signature protocol: $UDP_SIGNATURE" >&2
        echo "${PROTOCOL_MAP[$UDP_SIGNATURE]}"
    else
        warn "Protocol '$UDP_SIGNATURE' not found in PROTOCOL_MAP, falling back to QUIC" >&2
        echo "${PROTOCOL_MAP[QUIC]}"
    fi
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
# DNS resolution
# ===============================
resolve_host() {
    local host="$1"
    # Already an IPv4 address — return as-is
    if echo "$host" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        echo "$host"
        return 0
    fi
    # Resolve via nslookup (BusyBox, available on Alpine)
    # Skip first 2 lines (Server/Address header) then extract first IPv4
    local resolved
    resolved=$(nslookup "$host" 2>/dev/null | tail -n +3 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [ -n "$resolved" ]; then
        echo "$resolved"
        return 0
    fi
    # Fallback: try original DNS server (pre-VPN configuration)
    if [ -n "${ORIGINAL_DNS:-}" ]; then
        resolved=$(nslookup "$host" "$ORIGINAL_DNS" 2>/dev/null | tail -n +3 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if [ -n "$resolved" ]; then
            echo "$resolved"
            return 0
        fi
    fi
    warn "Failed to resolve hostname: $host"
    return 1
}

# Write tunnel state for metrics collector
# Usage: write_tunnel_state <healthy 0|1> [current_peer_basename] [failover_total] [last_failover_ts]
write_tunnel_state() {
    local healthy="${1:-0}"
    local current_peer="${2:-}"
    local failover_total="${3:-}"
    local last_failover_ts="${4:-}"
    local state_file="${TMP_DIR}/tunnel.state"
    local tmpfile
    tmpfile=$(mktemp)
    echo "tunnel_healthy=${healthy}" >> "$tmpfile"
    echo "last_check_ts=$(date +%s)" >> "$tmpfile"
    [ -n "$current_peer" ] && echo "current_peer=${current_peer}" >> "$tmpfile"
    [ -n "$failover_total" ] && echo "failover_total=${failover_total}" >> "$tmpfile"
    [ -n "$last_failover_ts" ] && echo "last_failover_ts=${last_failover_ts}" >> "$tmpfile"
    mv "$tmpfile" "$state_file"
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
                local endpoint_host endpoint_ip
                endpoint_host=$(conf_get_value "Endpoint" "$peer_file" | cut -d: -f1)
                if [ -n "$endpoint_host" ]; then
                    endpoint_ip=$(resolve_host "$endpoint_host") || continue
                    debug "Adding endpoint route: $endpoint_ip via $DEFAULT_GW dev $DEFAULT_IFACE (host: $endpoint_host)"
                    ip route add "$endpoint_ip" via "$DEFAULT_GW" dev "$DEFAULT_IFACE" 2>/dev/null || true
                fi
            done <<< "$peer_configs"
        fi

        if [ "$PROXY_SOCKS5_ENABLED" = "true" ] || [ "$PROXY_HTTP_ENABLED" = "true" ]; then
            # Source-based routing: 3proxy binds upstream sockets to the WG interface
            # IP (via the "external" directive in its config). Packets sourced from that
            # IP are routed through the tunnel via a dedicated routing table.
            local wg_ip
            wg_ip=$(ip addr show "$WG_IFACE" | awk '/inet / {print $2}' | cut -d/ -f1)

            if [ -z "$wg_ip" ]; then
                error "Cannot set up proxy routing: no IP assigned to $WG_IFACE"
                return 1
            fi

            ip route add default dev "$WG_IFACE" table 200
            ip rule add from "$wg_ip" table 200 priority 100

            debug "Source-based routing configured:"
            debug "- Traffic from $wg_ip ($WG_IFACE) -> WireGuard tunnel (table 200)"
            debug "- All other traffic -> Default interface ($DEFAULT_IFACE)"
        fi

        debug "- All peer endpoints -> Physical interface"

        if ping -c 2 -W 2 -I "$WG_IFACE" 8.8.8.8 >/dev/null 2>&1; then
            success "WireGuard connectivity test passed"
        else
            error "WireGuard connectivity test failed. Tunnel may be unhealthy."
        fi
    fi
}

# ===============================
# Proxy helpers
# ===============================

# Update the "external" directive in the 3proxy config and restart the process.
# Called by the monitor after a peer switch changes the WG interface IP.
proxy_update_external() {
    local new_ip="$1"
    local conf="$PROXY_CONF_DIR/3proxy.cfg"

    [ -f "$conf" ] || return 0

    sed -i "s|^external .*|external $new_ip|" "$conf"
    debug "Updated 3proxy config: external $new_ip"

    pkill 3proxy 2>/dev/null || true
    local kill_wait=0
    while pgrep -x 3proxy >/dev/null 2>&1 && [ $kill_wait -lt 25 ]; do
        sleep 0.2
        kill_wait=$((kill_wait + 1))
    done

    3proxy "$conf" &
    local proxy_pid=$!
    local start_wait=0
    while [ $start_wait -lt 50 ]; do
        kill -0 "$proxy_pid" 2>/dev/null || break
        netstat -tuln 2>/dev/null | grep -qE ":(${PROXY_SOCKS5_PORT}|${PROXY_HTTP_PORT}) " && break
        sleep 0.2
        start_wait=$((start_wait + 1))
    done

    if kill -0 "$proxy_pid" 2>/dev/null; then
        success "3proxy restarted with new external IP: $new_ip (PID: $proxy_pid)"
    else
        warn "3proxy failed to restart after external IP update"
    fi
}

# ===============================
# WireGuard interface helpers
# ===============================
start_wg_iface() {
    local iface="$1"

    debug "Starting amneziawg-go on $iface..."
    amneziawg-go "$iface" >>"$WG_LOGFILE" 2>&1 &

    local iface_wait=0
    while [ $iface_wait -lt 25 ]; do
        ip link show "$iface" >/dev/null 2>&1 && break
        sleep 0.2
        iface_wait=$((iface_wait + 1))
    done

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

# ===============================
# Password helpers
# ===============================

hash_pass() {
    printf "%s" "$1" | openssl passwd -1 -stdin
}
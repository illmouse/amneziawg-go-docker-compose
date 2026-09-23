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
# PID file of the amneziawg-go daemon (started with -f so it does not fork).
wg_pid_file() {
    echo "$TMP_DIR/amneziawg-$WG_IFACE.pid"
}

# UAPI control socket of the amneziawg-go daemon (per-upstream convention).
wg_uapi_socket() {
    echo "/var/run/amneziawg/$WG_IFACE.sock"
}

# Read the daemon PID from the pid file; empty if absent.
wg_daemon_pid() {
    local pid_file
    pid_file=$(wg_pid_file)
    [ -f "$pid_file" ] || return 0
    local pid
    pid=$(cat "$pid_file" 2>/dev/null)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || pid=""
    echo "$pid"
}

# True if the amneziawg-go daemon process is alive.
is_wg_daemon_alive() {
    [ -n "$(wg_daemon_pid)" ]
}

# Start amneziawg-go in the foreground (no fork) under shell background job
# control, record its PID, and wait for iface + UAPI socket + process liveness.
# Returns 0 only when the daemon verifiably came up.
start_wg_iface() {
    local iface="$1"
    local pid_file
    pid_file=$(wg_pid_file)
    local uapi_socket
    uapi_socket=$(wg_uapi_socket)

    debug "Starting amneziawg-go on $iface..."
    rm -f "$pid_file"
    amneziawg-go -f "$iface" >>"$WG_LOGFILE" 2>&1 &
    local daemon_pid=$!
    echo "$daemon_pid" > "$pid_file"

    # Wait up to 10s for: process alive + iface created + UAPI socket bound
    local wait=0
    while [ $wait -lt 50 ]; do
        if ! kill -0 "$daemon_pid" 2>/dev/null; then
            error "amneziawg-go exited immediately during startup on $iface"
            rm -f "$pid_file"
            return 1
        fi
        if ip link show "$iface" >/dev/null 2>&1 && [ -S "$uapi_socket" ]; then
            success "amneziawg-go started on $iface (PID: $daemon_pid)"
            if [ -n "$WG_MTU" ]; then
                ip link set dev "$iface" mtu "$WG_MTU" 2>/dev/null || warn "Failed to set MTU $WG_MTU on $iface"
            fi
            return 0
        fi
        sleep 0.2
        wait=$((wait + 1))
    done

    error "amneziawg-go did not come up on $iface within 10s"
    kill "$daemon_pid" 2>/dev/null || true
    rm -f "$pid_file"
    return 1
}

# Stop the amneziawg-go daemon: SIGTERM (graceful) -> SIGKILL fallback.
# Also sweeps orphans matching "amneziawg-go <iface>", removes the interface
# and the stale UAPI socket (the 2026-09-03 crash-revival root cause).
stop_wg_iface() {
    local iface="$1"
    local pid_file
    pid_file=$(wg_pid_file)
    local uapi_socket
    uapi_socket=$(wg_uapi_socket)

    debug "Stopping amneziawg-go on $iface..."

    local pid
    pid=$(wg_daemon_pid)
    if [ -n "$pid" ]; then
        kill "$pid" 2>/dev/null || true
    else
        # Daemon not tracked (e.g. pid file lost) — sweep any orphans
        pkill -f "amneziawg-go -f $iface" 2>/dev/null || true
        pkill -f "amneziawg-go $iface" 2>/dev/null || true
    fi

    # Wait up to 5s for graceful exit
    local term_wait=0
    while pgrep -f "amneziawg-go (-f )?$iface" >/dev/null 2>&1 && [ $term_wait -lt 25 ]; do
        sleep 0.2
        term_wait=$((term_wait + 1))
    done

    # Escalate to SIGKILL if still alive
    if pgrep -f "amneziawg-go (-f )?$iface" >/dev/null 2>&1; then
        warn "amneziawg-go on $iface did not exit after SIGTERM, sending SIGKILL"
        pkill -9 -f "amneziawg-go (-f )?$iface" 2>/dev/null || true
        sleep 0.5
    fi

    rm -f "$pid_file"

    # Remove leftover interface (dead daemon leaves it behind)
    if ip link show "$iface" >/dev/null 2>&1; then
        ip link del "$iface" 2>/dev/null || true
    fi

    # Remove stale UAPI socket so a restarted daemon can bind it
    [ -S "$uapi_socket" ] || [ -e "$uapi_socket" ] && rm -f "$uapi_socket"

    debug "amneziawg-go on $iface stopped"
    return 0
}

# Full in-place revival: stop (idempotent) -> start -> re-apply config.
# Config re-application is mode-specific and passed as the second argument:
# a callback invoked once the daemon is back up (e.g. reload_server_wg_conf).
# Returns 0 when the tunnel is verifiably listening again.
revive_wg_iface() {
    local iface="$1"
    local reapply_fn="${2:-}"

    warn "Reviving amneziawg-go on $iface..."

    stop_wg_iface "$iface"

    if ! start_wg_iface "$iface"; then
        error "Failed to restart amneziawg-go on $iface"
        return 1
    fi

    if [ -n "$reapply_fn" ] && ! "$reapply_fn"; then
        error "Failed to re-apply WireGuard configuration on $iface after revival"
        return 1
    fi

    if ! is_wg_listening; then
        error "amneziawg-go on $iface is not listening after revival"
        return 1
    fi

    success "amneziawg-go on $iface revived successfully"
    return 0
}

# Re-apply the server config after revival: address, setconf, link up.
# iptables rules live in the kernel and survive daemon death — not re-applied.
reload_server_wg_conf() {
    ip address add dev "$WG_IFACE" "$WG_ADDRESS" 2>/dev/null || true
    if ! awg setconf "$WG_IFACE" "$WG_DIR/$WG_CONF_FILE" 2>>"$WG_LOGFILE"; then
        error "Failed to reload WireGuard config after restart"
        return 1
    fi
    ip link set up dev "$WG_IFACE" 2>/dev/null || true
    return 0
}

# Re-apply the client config after revival: setconf, link up, address.
reload_client_wg_conf() {
    if ! awg setconf "$WG_IFACE" "$WG_DIR/$WG_CONF_FILE" 2>>"$WG_LOGFILE"; then
        error "Failed to reload client WireGuard config after restart"
        return 1
    fi
    ip link set up dev "$WG_IFACE" 2>/dev/null || true
    if [ -n "$WG_ADDRESS" ]; then
        ip address add dev "$WG_IFACE" "$WG_ADDRESS" 2>/dev/null || true
    fi
    return 0
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
    if [ ! -f "$config_file" ];        then
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

# Zombie detection: iface exists but daemon process is dead (OOM-kill etc.)
# or its UAPI socket is gone/stale.
is_wg_daemon_dead() {
    # No iface -> daemon cannot be alive for our purposes; let rc=2 path handle
    ip link show "$WG_IFACE" >/dev/null 2>&1 || return 1
    # Iface exists but daemon process gone -> zombie
    if ! is_wg_daemon_alive; then
        return 0
    fi
    # Iface + daemon alive but socket missing -> stale state
    local uapi_socket
    uapi_socket=$(wg_uapi_socket)
    [ -S "$uapi_socket" ] || return 0
    return 1
}

# ===============================
# AmneziaWG 3.1 parameter validation
# ===============================
# Validates opt-in 3.1 params. All have empty defaults (pre-3.1 behavior).
validate_awg31_params() {
    local errors=0

    # HeaderProtectionKey: server-side, 32-byte base64, requires S1-S4 >= 12
    if [ -n "$HeaderProtectionKey" ]; then
        local decoded_len
        decoded_len=$(printf '%s' "$HeaderProtectionKey" | openssl base64 -d -A 2>/dev/null | wc -c)
        if [ "$decoded_len" -ne 32 ] 2>/dev/null; then
            error "HeaderProtectionKey must be a base64-encoded 32-byte key (got $decoded_len bytes after decode)"
            errors=$((errors + 1))
        fi
        local s_param
        for s_param in S1 S2 S3 S4; do
            if [ "${!s_param}" -lt 12 ]; then
                error "HeaderProtectionKey requires $s_param >= 12 (current: ${!s_param})"
                errors=$((errors + 1))
            fi
        done
    fi

    # Range params: single value 'a' or inclusive range 'a-b'
    local range_param
    for range_param in ContentPaddingAddition RekeyAfterTime RekeyTimeout \
                      RejectAfterTime KeepaliveTimeout MaxHandshakeAttempts; do
        local value="${!range_param}"
        [ -z "$value" ] && continue
        if ! printf '%s' "$value" | grep -qE '^[0-9]+(-[0-9]+)?$'; then
            error "$range_param must be a number or range 'a-b' (current: $value)"
            errors=$((errors + 1))
        fi
    done

    # on/off params
    local toggle_param
    for toggle_param in RandomTrailers DisableCookies; do
        local value="${!toggle_param}"
        [ -z "$value" ] && continue
        case "$value" in
            on|off) ;;
            *)
                error "$toggle_param must be 'on' or 'off' (current: $value)"
                errors=$((errors + 1))
                ;;
        esac
    done

    # Non-fatal: S4 > 20 makes worst-case data packets exceed a 1500-byte path MTU
    if [ "${S4:-0}" -gt 20 ]; then
        warn "S4=${S4} makes worst-case data packets ${S4} bytes larger than standard WireGuard (1480 + S4 = $((1480 + S4)) bytes outer) — they will exceed a 1500-byte path MTU and fragment. Consider S4 <= 20 or set WG_MTU lower (e.g. $((1472 - S4)) or less) on both server and clients."
    fi

    if [ "$errors" -gt 0 ]; then
        error "AmneziaWG 3.1 parameter validation failed with $errors error(s)"
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
#!/bin/bash
set -eu

. /entrypoint/lib/env.sh
. /entrypoint/lib/functions.sh

METRICS_FILE="${TMP_DIR}/metrics.prom"
TUNNEL_STATE="${TMP_DIR}/tunnel.state"

state_get() {
    local key="$1" val
    [ -f "$TUNNEL_STATE" ] || return 1
    val=$(grep "^${key}=" "$TUNNEL_STATE" 2>/dev/null | cut -d= -f2- | head -1)
    [ -n "$val" ] || return 1
    echo "$val"
}

collect_server_metrics() {
    local tmp="$1" now="$2"
    local total=0 active=0 stale=0

    cat >> "$tmp" <<'PROM'
# HELP wg_server_peers_total Total number of configured peers on the server
# TYPE wg_server_peers_total gauge
# HELP wg_server_peers_active Number of peers with a handshake within PEER_HANDSHAKE_TIMEOUT seconds
# TYPE wg_server_peers_active gauge
# HELP wg_server_peers_stale Number of peers whose last handshake exceeds PEER_HANDSHAKE_TIMEOUT seconds (or never connected)
# TYPE wg_server_peers_stale gauge
PROM

    while IFS=$'\t' read -r _iface _pubkey _psk _endpoint _allowed handshake _rx _tx _ka; do
        [ "$_iface" = "$WG_IFACE" ] || continue
        total=$(( total + 1 ))
        if [ "${handshake:-0}" != "0" ] && [[ "${handshake}" =~ ^[0-9]+$ ]]; then
            local age=$(( now - handshake ))
            if [ "$age" -le "${PEER_HANDSHAKE_TIMEOUT}" ]; then
                active=$(( active + 1 ))
            else
                stale=$(( stale + 1 ))
            fi
        else
            stale=$(( stale + 1 ))
        fi
    done < <(awg show all dump 2>/dev/null | awk -F'\t' 'NF==9')

    echo "wg_server_peers_total{interface=\"${WG_IFACE}\"} ${total}" >> "$tmp"
    echo "wg_server_peers_active{interface=\"${WG_IFACE}\"} ${active}" >> "$tmp"
    echo "wg_server_peers_stale{interface=\"${WG_IFACE}\"} ${stale}" >> "$tmp"
}

collect() {
    local now
    now=$(date +%s)
    local tmp
    tmp=$(mktemp)

    # ---- Interface up ----
    cat >> "$tmp" <<'PROM'
# HELP wg_interface_up WireGuard interface operational status (1=up, 0=down)
# TYPE wg_interface_up gauge
PROM
    if ip link show "$WG_IFACE" >/dev/null 2>&1; then
        echo "wg_interface_up{interface=\"${WG_IFACE}\"} 1" >> "$tmp"
    else
        echo "wg_interface_up{interface=\"${WG_IFACE}\"} 0" >> "$tmp"
    fi

    # ---- Build info ----
    cat >> "$tmp" <<'PROM'
# HELP wg_build_info Version info for the running AmneziaWG instance (always 1)
# TYPE wg_build_info gauge
PROM
    local awg_version
    awg_version=$(awg --version 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"\\' || true)
    awg_version="${awg_version:-unknown}"
    echo "wg_build_info{interface=\"${WG_IFACE}\",awg_version=\"${awg_version}\"} 1" >> "$tmp"

    # ---- Peer configuration info + endpoint→name map (client mode) ----
    # Built before the per-peer metrics loop so the map can enrich traffic metrics with peer names.
    declare -A _peer_map
    cat >> "$tmp" <<'PROM'
# HELP wg_peer_info Configured peer info (always 1); use label fields for identification
# TYPE wg_peer_info gauge
PROM
    if [ "$WG_MODE" = "server" ] && [ -f "$CONFIG_DB" ]; then
        while IFS=$'\t' read -r p_pubkey p_name p_ip; do
            echo "wg_peer_info{interface=\"${WG_IFACE}\",peer=\"${p_name}\",public_key=\"${p_pubkey}\",allowed_ip=\"${p_ip}/32\"} 1" >> "$tmp"
        done < <(jq -r '.peers | to_entries[] | "\(.value.public_key)\t\(.key)\t\(.value.ip)"' "$CONFIG_DB" 2>/dev/null || true)
    elif [ "$WG_MODE" = "client" ]; then
        for p_file in "${CLIENT_PEERS_DIR}"/*.conf; do
            [ -f "$p_file" ] || continue
            local p_name p_ep_raw p_ep_host p_ep_port p_ep_ip p_endpoint
            p_name=$(basename "$p_file")
            p_ep_raw=$(grep -E "^Endpoint[[:space:]]*=" "$p_file" 2>/dev/null | head -1 | sed 's/^Endpoint[[:space:]]*=[[:space:]]*//' | tr -d '\r\n' || true)
            if [ -n "$p_ep_raw" ]; then
                p_ep_host=$(echo "$p_ep_raw" | cut -d: -f1)
                p_ep_port=$(echo "$p_ep_raw" | cut -d: -f2)
                p_ep_ip=$(resolve_host "$p_ep_host" 2>/dev/null) || p_ep_ip="$p_ep_host"
                p_endpoint="${p_ep_ip}:${p_ep_port}"
            else
                p_endpoint="unknown"
            fi
            _peer_map["$p_endpoint"]="$p_name"
            echo "wg_peer_info{interface=\"${WG_IFACE}\",peer=\"${p_name}\",endpoint=\"${p_endpoint}\"} 1" >> "$tmp"
        done
    fi

    # ---- Per-peer metrics from awg show all dump ----
    # Peer lines have 9 tab-separated fields; interface lines have 5 — filter by NF==9
    # In client mode, the peer label is added from the endpoint→name map built above.
    cat >> "$tmp" <<'PROM'
# HELP wg_peer_last_handshake_timestamp_seconds Unix timestamp of the last successful handshake (0 if never)
# TYPE wg_peer_last_handshake_timestamp_seconds gauge
# HELP wg_peer_handshake_age_seconds Seconds elapsed since the last successful handshake (0 if never)
# TYPE wg_peer_handshake_age_seconds gauge
# HELP wg_peer_rx_bytes_total Total bytes received from this peer
# TYPE wg_peer_rx_bytes_total counter
# HELP wg_peer_tx_bytes_total Total bytes transmitted to this peer
# TYPE wg_peer_tx_bytes_total counter
PROM
    while IFS=$'\t' read -r iface pubkey _psk endpoint _allowed handshake rx tx _ka; do
        [ "$iface" = "$WG_IFACE" ] || continue
        local age=0
        if [ "${handshake:-0}" != "0" ] && [[ "${handshake}" =~ ^[0-9]+$ ]]; then
            age=$(( now - handshake ))
            [ "$age" -lt 0 ] && age=0
        fi
        local peer_lbl=""
        if [ "$WG_MODE" = "client" ]; then
            local mapped_peer="${_peer_map[$endpoint]:-}"
            [ -n "$mapped_peer" ] && peer_lbl=",peer=\"${mapped_peer}\""
        fi
        local lbl="interface=\"${iface}\",public_key=\"${pubkey}\",endpoint=\"${endpoint}\"${peer_lbl}"
        echo "wg_peer_last_handshake_timestamp_seconds{${lbl}} ${handshake:-0}" >> "$tmp"
        echo "wg_peer_handshake_age_seconds{${lbl}} ${age}" >> "$tmp"
        echo "wg_peer_rx_bytes_total{${lbl}} ${rx:-0}" >> "$tmp"
        echo "wg_peer_tx_bytes_total{${lbl}} ${tx:-0}" >> "$tmp"
    done < <(awg show all dump 2>/dev/null | awk -F'\t' 'NF==9')

    # ---- Tunnel health (from monitor state file) ----
    cat >> "$tmp" <<'PROM'
# HELP wg_tunnel_healthy Whether the tunnel health check is currently passing (1=healthy, 0=unhealthy)
# TYPE wg_tunnel_healthy gauge
# HELP wg_tunnel_last_check_timestamp_seconds Unix timestamp of the last health check run
# TYPE wg_tunnel_last_check_timestamp_seconds gauge
PROM
    local healthy last_check
    healthy=$(state_get tunnel_healthy) || true
    last_check=$(state_get last_check_ts) || true
    echo "wg_tunnel_healthy{interface=\"${WG_IFACE}\"} ${healthy:-0}" >> "$tmp"
    echo "wg_tunnel_last_check_timestamp_seconds{interface=\"${WG_IFACE}\"} ${last_check:-0}" >> "$tmp"

    # ---- Interface traffic (from /proc/net/dev) ----
    cat >> "$tmp" <<'PROM'
# HELP wg_interface_rx_bytes_total Total bytes received on the WireGuard interface
# TYPE wg_interface_rx_bytes_total counter
# HELP wg_interface_tx_bytes_total Total bytes transmitted on the WireGuard interface
# TYPE wg_interface_tx_bytes_total counter
PROM
    local iface_line iface_rx iface_tx
    iface_line=$(grep "^\s*${WG_IFACE}:" /proc/net/dev 2>/dev/null || true)
    iface_rx=0; iface_tx=0
    if [ -n "$iface_line" ]; then
        iface_rx=$(echo "$iface_line" | awk -F: '{print $2}' | awk '{print $1}')
        iface_tx=$(echo "$iface_line" | awk -F: '{print $2}' | awk '{print $9}')
    fi
    echo "wg_interface_rx_bytes_total{interface=\"${WG_IFACE}\"} ${iface_rx:-0}" >> "$tmp"
    echo "wg_interface_tx_bytes_total{interface=\"${WG_IFACE}\"} ${iface_tx:-0}" >> "$tmp"

    # ---- Server-mode-only metrics ----
    if [ "$WG_MODE" = "server" ]; then
        collect_server_metrics "$tmp" "$now"
    fi

    # ---- Client-mode-only metrics ----
    if [ "$WG_MODE" = "client" ]; then
        cat >> "$tmp" <<'PROM'
# HELP wg_tunnel_failover_total Total number of peer failover events since container start
# TYPE wg_tunnel_failover_total counter
# HELP wg_tunnel_last_failover_timestamp_seconds Unix timestamp of the most recent peer failover (0 if none since container start)
# TYPE wg_tunnel_last_failover_timestamp_seconds gauge
# HELP wg_tunnel_active_peer Whether this peer config is the currently active one (1=active, 0=inactive)
# TYPE wg_tunnel_active_peer gauge
PROM
        local failover last_failover
        failover=$(state_get failover_total) || true
        last_failover=$(state_get last_failover_ts) || true
        echo "wg_tunnel_failover_total{interface=\"${WG_IFACE}\"} ${failover:-0}" >> "$tmp"
        echo "wg_tunnel_last_failover_timestamp_seconds{interface=\"${WG_IFACE}\"} ${last_failover:-0}" >> "$tmp"

        local current_peer
        current_peer=$(state_get current_peer) || true
        for peer_file in "${CLIENT_PEERS_DIR}"/*.conf; do
            [ -f "$peer_file" ] || continue
            local peer_name active=0
            peer_name=$(basename "$peer_file")
            [ "$peer_name" = "$current_peer" ] && active=1
            echo "wg_tunnel_active_peer{interface=\"${WG_IFACE}\",peer=\"${peer_name}\"} ${active}" >> "$tmp"
        done
    fi

    mv "$tmp" "$METRICS_FILE"
}

info "Metrics collector started (interval=${METRICS_INTERVAL}s)"

# Collect immediately on startup so metrics are available before first sleep
collect || warn "Initial metrics collection failed, will retry"

while true; do
    sleep "$METRICS_INTERVAL"
    collect || warn "Metrics collection failed, retrying next interval"
done

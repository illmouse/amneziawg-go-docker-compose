#!/bin/bash
set -eu

. /entrypoint/lib/env.sh
. /entrypoint/lib/functions.sh

METRICS_FILE="${TMP_DIR}/metrics.prom"
TUNNEL_STATE="${TMP_DIR}/tunnel.state"

state_get() {
    local key="$1"
    [ -f "$TUNNEL_STATE" ] || { echo ""; return 0; }
    grep "^${key}=" "$TUNNEL_STATE" 2>/dev/null | cut -d= -f2- | head -1
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

    # ---- Per-peer metrics from awg show all dump ----
    # Peer lines have 9 tab-separated fields; interface lines have 5 — filter by NF==9
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
        if [ "${handshake:-0}" != "0" ]; then
            age=$(( now - handshake ))
            [ "$age" -lt 0 ] && age=0
        fi
        local lbl="interface=\"${iface}\",public_key=\"${pubkey}\",endpoint=\"${endpoint}\""
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
    echo "wg_tunnel_healthy{interface=\"${WG_IFACE}\"} $(state_get tunnel_healthy || echo 0)" >> "$tmp"
    echo "wg_tunnel_last_check_timestamp_seconds{interface=\"${WG_IFACE}\"} $(state_get last_check_ts || echo 0)" >> "$tmp"

    # ---- Client-mode-only metrics ----
    if [ "$WG_MODE" = "client" ]; then
        cat >> "$tmp" <<'PROM'
# HELP wg_tunnel_failover_total Total number of peer failover events since container start
# TYPE wg_tunnel_failover_total counter
# HELP wg_tunnel_active_peer Whether this peer config is the currently active one (1=active, 0=inactive)
# TYPE wg_tunnel_active_peer gauge
PROM
        echo "wg_tunnel_failover_total{interface=\"${WG_IFACE}\"} $(state_get failover_total || echo 0)" >> "$tmp"

        local current_peer
        current_peer=$(state_get current_peer || echo "")
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
collect

while true; do
    sleep "$METRICS_INTERVAL"
    collect
done

#!/bin/bash
. /entrypoint/functions.sh

debug "${NETWORK_EMOJI} Starting WireGuard interface $WG_IFACE in SERVER mode..."

start_wg_iface "$WG_IFACE"

debug "SERVER MODE: Assigning address $WG_ADDRESS to $WG_IFACE..."
ip address add dev "$WG_IFACE" "$WG_ADDRESS" 2>>"$WG_LOGFILE" || true

debug "Loading server config into $WG_IFACE..."
if ! awg setconf "$WG_IFACE" "$WG_DIR/$WG_CONF_FILE" >>"$WG_LOGFILE" 2>&1; then
    error "Failed to load WireGuard configuration"
fi

debug "Bringing interface up..."
ip link set up dev "$WG_IFACE" >>"$WG_LOGFILE" 2>&1

debug "Adding iptables rules..."
DEF_IFACE=$(ip route | awk '/default/ {print $5; exit}')
iptables -t nat -A POSTROUTING -o "$DEF_IFACE" -j MASQUERADE 2>>"$WG_LOGFILE" || true
iptables -A FORWARD -i "$WG_IFACE" -j ACCEPT 2>>"$WG_LOGFILE" || true
iptables -A INPUT -i "$WG_IFACE" -j ACCEPT 2>>"$WG_LOGFILE" || true

success "${NETWORK_EMOJI} Server setup complete. Interface $WG_IFACE is up."

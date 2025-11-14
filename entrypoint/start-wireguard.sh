#!/bin/sh

. /entrypoint/functions.sh

log "Starting WireGuard interface $WG_IFACE..."

log "Starting amneziawg-go on $WG_IFACE..."
amneziawg-go "$WG_IFACE" >>"$WG_LOGFILE" 2>&1 &
sleep 2

log "Assigning address $WG_ADDRESS to $WG_IFACE..."
ip address add dev "$WG_IFACE" "$WG_ADDRESS" 2>>"$WG_LOGFILE" || true

log "Loading config into $WG_IFACE..."
awg setconf "$WG_IFACE" "$WG_DIR/$WG_CONF_FILE" >>"$WG_LOGFILE" 2>&1 || log "[WARN] awg setconf failed"

log "Bringing interface up..."
ip link set up dev "$WG_IFACE" >>"$WG_LOGFILE" 2>&1

log "Adding iptables rules..."
DEF_IFACE=$(ip route | awk '/default/ {print $5; exit}')

# Enable forwarding/NAT through the same interface
iptables -t nat -A POSTROUTING -o "$DEF_IFACE" -j MASQUERADE 2>>"$WG_LOGFILE" || true
iptables -A FORWARD -i "$WG_IFACE" -j ACCEPT 2>>"$WG_LOGFILE" || true
iptables -A INPUT -i "$WG_IFACE" -j ACCEPT 2>>"$WG_LOGFILE" || true

log "WireGuard setup complete. Interface $WG_IFACE is up."
log "Configuration database: $CONFIG_DB"
log "Peer configurations available in: $PEERS_DIR/"
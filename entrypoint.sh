#!/bin/sh
set -eu

WG_DIR="/etc/amneziawg"
TMP_DIR="/tmp/amneziawg"
WG_CONF_FILE="wg0.conf"
WG_PEER_FILE="peer.conf"
WG_LOGFILE="/var/log/amneziawg/amneziawg.log"

mkdir -p "$WG_DIR" "$TMP_DIR"
: > "$WG_LOGFILE"

# Load environment variables
: "${WG_IFACE:=wg0}"
: "${WG_ADDRESS:=10.100.0.1/24}"
: "${WG_CLIENT_ADDR:=10.100.0.2/32}"
: "${WG_PORT:=13440}"
: "${WG_ENDPOINT:=}"

: "${Jc:=3}"
: "${Jmin:=1}"
: "${Jmax:=50}"
: "${S1:=25}"
: "${S2:=72}"
: "${H1:=1411927821}"
: "${H2:=1212681123}"
: "${H3:=1327217326}"
: "${H4:=1515483925}"

log() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*" | tee -a "$WG_LOGFILE"; }

# Key files
SERVER_PRIV="$WG_DIR/privatekey"
SERVER_PUB="$WG_DIR/publickey"
PSK_KEY="$WG_DIR/presharedkey"
CLIENT_PRIV="$WG_DIR/client_privatekey"

# Helper: generate keys if missing
gen_key()  { awg genkey 2>/dev/null | tr -d '\n\r'; }
gen_psk()  { awg genpsk 2>/dev/null | tr -d '\n\r'; }
pub_from_priv() { echo "$1" | awg pubkey 2>/dev/null | tr -d '\n\r'; }

# 1️⃣ Server keys
if [ ! -f "$SERVER_PRIV" ]; then
  log "Generating server private key..."
  SERVER_PRIV_KEY=$(gen_key)
  echo "$SERVER_PRIV_KEY" > "$SERVER_PRIV"
  chmod 600 "$SERVER_PRIV"
else
  SERVER_PRIV_KEY=$(cat "$SERVER_PRIV")
fi

if [ ! -f "$SERVER_PUB" ]; then
  log "Deriving server public key..."
  SERVER_PUB_KEY=$(pub_from_priv "$SERVER_PRIV_KEY")
  echo "$SERVER_PUB_KEY" > "$SERVER_PUB"
  chmod 600 "$SERVER_PUB"
else
  SERVER_PUB_KEY=$(cat "$SERVER_PUB")
fi

if [ ! -f "$PSK_KEY" ]; then
  log "Generating preshared key..."
  PSK=$(gen_psk)
  echo "$PSK" > "$PSK_KEY"
  chmod 600 "$PSK_KEY"
else
  PSK=$(cat "$PSK_KEY")
fi

# 2️⃣ Client key
CLIENT_PRIV="$WG_DIR/client_privatekey"
if [ ! -f "$CLIENT_PRIV" ]; then
  log "Generating client private key..."
  CLIENT_PRIV_KEY=$(gen_key)
  echo "$CLIENT_PRIV_KEY" > "$CLIENT_PRIV"
  chmod 600 "$CLIENT_PRIV"
else
  CLIENT_PRIV_KEY=$(cat "$CLIENT_PRIV")
fi
CLIENT_PUB_KEY=$(pub_from_priv "$CLIENT_PRIV_KEY")

# 3️⃣ Generate server config
TMP_CONF="$TMP_DIR/$WG_CONF_FILE"
cat > "$TMP_CONF" <<EOF
[Interface]
PrivateKey = $SERVER_PRIV_KEY
ListenPort = $WG_PORT
Jc = $Jc
Jmin = $Jmin
Jmax = $Jmax
S1 = $S1
S2 = $S2
H1 = $H1
H2 = $H2
H3 = $H3
H4 = $H4

[Peer]
PublicKey = $CLIENT_PUB_KEY
PresharedKey = $PSK
AllowedIPs = $WG_CLIENT_ADDR
EOF

CONF_PATH="$WG_DIR/$WG_CONF_FILE"
if [ -f "$CONF_PATH" ]; then
  if cmp -s "$TMP_CONF" "$CONF_PATH"; then
    log "Server config unchanged."
  else
    log "Server config differs. Overwriting $CONF_PATH."
    cp "$TMP_CONF" "$CONF_PATH"
  fi
else
  log "Creating server config $CONF_PATH."
  cp "$TMP_CONF" "$CONF_PATH"
fi

# 4️⃣ Generate peer/client config
PEER_PATH="$WG_DIR/$WG_PEER_FILE"
cat > "$PEER_PATH" <<EOF
[Interface]
PrivateKey = $CLIENT_PRIV_KEY
Address = $WG_CLIENT_ADDR
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB_KEY
PresharedKey = $PSK
Endpoint = $WG_ENDPOINT:$WG_PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

log "Client config written to $PEER_PATH."

# 5️⃣ Start amneziawg-go and configure interface
log "Starting amneziawg-go on $WG_IFACE..."
amneziawg-go "$WG_IFACE" >>"$WG_LOGFILE" 2>&1 &
sleep 2

log "Assigning address $WG_ADDRESS to $WG_IFACE..."
ip address add dev "$WG_IFACE" "$WG_ADDRESS" 2>>"$WG_LOGFILE" || true

log "Loading config into $WG_IFACE..."
awg setconf "$WG_IFACE" "$CONF_PATH" >>"$WG_LOGFILE" 2>&1 || log "[WARN] awg setconf failed"

log "Bringing interface up..."
ip link set up dev "$WG_IFACE" >>"$WG_LOGFILE" 2>&1

# Enable forwarding/NAT through the same interface
iptables -t nat -A POSTROUTING -o "$WG_IFACE" -j MASQUERADE 2>>"$WG_LOGFILE" || true
iptables -A FORWARD -i "$WG_IFACE" -j ACCEPT 2>>"$WG_LOGFILE" || true
iptables -A FORWARD -o "$WG_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>>"$WG_LOGFILE" || true

log "Setup complete. Interface $WG_IFACE is up and peer.conf available."
tail -F "$WG_LOGFILE"

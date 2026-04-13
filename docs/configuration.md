# Configuration

## Environment Variables

All variables are set in `.env` (copy from `.env.example`). Loaded at container start from `/etc/amneziawg/.env`.

### Core (required)

| Variable | Default | Description |
|----------|---------|-------------|
| `WG_ENDPOINT` | _(none)_ | Public IP or hostname of the server. Required for server mode. |
| `WG_MODE` | `server` | Operation mode: `server` or `client` |

### WireGuard

| Variable | Default | Description |
|----------|---------|-------------|
| `WG_IFACE` | `wg0` | WireGuard interface name inside container |
| `WG_ADDRESS` | `10.100.0.1/24` | Server VPN IP and subnet |
| `WG_PORT` | `13440` | UDP port to listen on (server) / connect to (client) |
| `WG_PEER_COUNT` | `1` | Number of peer configs to generate (server mode) |
| `MASTER_PEER` | `peer1.conf` | Client mode: preferred peer filename; switched back to when it recovers |
| `LOG_LEVEL` | `INFO` | Log verbosity: `ERROR`, `WARN`, `INFO`, `DEBUG` |

### UDP Obfuscation

| Variable | Default | Description |
|----------|---------|-------------|
| `UDP_SIGNATURE` | `QUIC` | Protocol disguise: `SIP`, `DNS`, `QUIC`, `STUN-WEBRTC` |
| `Jc` | `3` | Number of junk packets per handshake |
| `Jmin` | `1` | Minimum junk packet size (bytes) |
| `Jmax` | `50` | Maximum junk packet size (bytes) |
| `S1` | `25` | Init packet size adjustment |
| `S2` | `72` | Response packet size adjustment |
| `S3` | `25` | Additional size adjustment |
| `S4` | `76` | Additional size adjustment |
| `H1`–`H4` | _(set)_ | Magic header constants for obfuscation |

### Proxy (client mode)

| Variable | Default | Description |
|----------|---------|-------------|
| `PROXY_SOCKS5_ENABLED` | `true` | Enable SOCKS5 proxy via 3proxy |
| `PROXY_SOCKS5_PORT` | `4128` | SOCKS5 listen port |
| `PROXY_SOCKS5_AUTH_ENABLED` | `false` | Require authentication for SOCKS5 |
| `PROXY_SOCKS5_AUTH_USER` | `user1` | SOCKS5 username |
| `PROXY_SOCKS5_AUTH_PASSWORD` | _(none)_ | SOCKS5 password |
| `PROXY_HTTP_ENABLED` | `false` | Enable HTTP proxy via 3proxy |
| `PROXY_HTTP_PORT` | `3128` | HTTP proxy listen port |
| `PROXY_HTTP_AUTH_ENABLED` | `false` | Require authentication for HTTP proxy |
| `PROXY_HTTP_AUTH_USER` | `user1` | HTTP proxy username |
| `PROXY_HTTP_AUTH_PASSWORD` | _(none)_ | HTTP proxy password |
| `PROXY_CUSTOM_CONFIG` | `false` | Use a custom 3proxy config mounted at `/etc/3proxy/3proxy.cfg` |

### Monitoring

| Variable | Default | Description |
|----------|---------|-------------|
| `MON_CHECK_IP` | `9.9.9.9` | IP pinged through tunnel to verify health |
| `MON_CHECK_INTERVAL` | `10` | Seconds between health checks |
| `MON_CHECK_TIMEOUT` | `10` | Ping timeout (seconds) |
| `MON_PING_COUNT` | `3` | Number of ping packets sent per health check. The check passes if any packet gets a response (client mode) |

### Prometheus Metrics

| Variable | Default | Description |
|----------|---------|-------------|
| `METRICS_ENABLED` | `false` | Enable Prometheus metrics endpoint |
| `METRICS_PORT` | `9586` | Port to serve `/metrics` |
| `METRICS_INTERVAL` | `15` | Collection interval (seconds) |
| `PEER_HANDSHAKE_TIMEOUT` | `180` | Seconds since last handshake before a peer is considered disconnected (server mode) |

### Log Rotation

| Variable | Default | Description |
|----------|---------|-------------|
| `LOGROTATE_INTERVAL` | `86400` | Seconds between rotation runs (default 24 h) |
| `LOGROTATE_ROTATE` | `1` | Number of rotated log files to keep |
| `LOGROTATE_MAXAGE` | `1` | Delete rotated files older than N days |

## Config File Locations

Inside the container, `./config/` is mounted to `/etc/amneziawg/`.

```
config/
├── .env                  # Runtime env (copied from project root .env)
├── keys/                 # Server keypair (server mode, auto-generated)
├── config.json           # Peer database (server mode, auto-generated)
├── server_peers/         # Per-peer client configs (server mode)
│   ├── peer1.conf
│   ├── peer1.png         # QR code for mobile import
│   └── ...
└── client_peers/         # Peer configs for client to connect to
    ├── peer1.conf
    └── ...
```

### Peer config format (`client_peers/*.conf`)

Standard WireGuard `[Interface]` + `[Peer]` sections with AmneziaWG obfuscation fields (`Jc`, `Jmin`, `Jmax`, `S1`–`S4`, `H1`–`H4`) added to `[Interface]`.

## Ports (docker-compose.yaml)

Only `WG_PORT/udp` is exposed by default. Uncomment additional lines to expose:

```yaml
# - ${PROXY_SOCKS5_PORT}:${PROXY_SOCKS5_PORT}/tcp
# - ${PROXY_HTTP_PORT}:${PROXY_HTTP_PORT}/tcp
# - ${METRICS_PORT}:${METRICS_PORT}/tcp
```

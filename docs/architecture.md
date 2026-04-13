# Architecture

## Container

Single Docker Compose service `awg` running image `ghcr.io/illmouse/amneziawg-go:latest` (Alpine-based).

```
docker-compose.yaml
└── awg (amneziawg container)
    ├── cap_add: NET_ADMIN
    ├── devices: /dev/net/tun
    ├── sysctls: ip_forward=1, src_valid_mark=1
    ├── volumes:
    │   ├── ./config → /etc/amneziawg
    │   └── ./logs  → /var/log/amneziawg
    └── ports: WG_PORT/udp (default 13440)
```

## Modes

### Server mode (`WG_MODE=server`)

Entrypoint flow (`entrypoint/main.sh`):

1. `validate_environment` — checks required vars
2. `ensure_directories` — creates runtime dirs
3. `server/init_db.sh` — initializes `config.json` peer DB
4. `server/keys.sh` — generates server keypair (stored in `config/keys/`)
5. `server/peers.sh` — creates/manages `WG_PEER_COUNT` peers
6. `server/generate_configs.sh` — writes `wg0.conf` and per-peer client configs
7. `fix_permissions` — locks down key files
8. `server/start.sh` — brings up the WireGuard interface
9. Background: `server/monitor.sh`, `logrotate.sh`, metrics (if enabled)

Peer configs are stored in `config/server_peers/` (one `.conf` per peer).

#### Server monitor watchdog

`server/monitor.sh` runs `check_container_health` on each iteration. Exit codes:

| Code | Meaning |
|------|---------|
| 0 | Healthy |
| 1 | Unhealthy — ping, config, or listen failure |
| 2 | `wg0` interface absent (`amneziawg-go` crashed) |

On exit code 2, the monitor calls `restart_wg_iface()` to attempt an in-place interface restart without touching the container. After **3 consecutive failed restart attempts** it sends `kill 1` to force a full container restart; Docker's `restart: always` policy then brings the container back up cleanly.

### Client mode (`WG_MODE=client`)

Entrypoint flow:

1. `validate_environment`
2. `ensure_directories`
3. `client/assemble_config.sh` — picks active peer from `config/client_peers/`
4. `fix_permissions`
5. `client/start.sh` — brings up WireGuard client interface
6. `client/proxy.sh` — starts 3proxy if enabled
7. Background: `client/monitor.sh`, `logrotate.sh`, metrics (if enabled)

#### Smart switchover

`client/monitor.sh` continuously probes tunnel health via ICMP ping through the `WG_IFACE` interface. On failure it:

- Probes each peer config in `config/client_peers/` using a temporary `awg-probe-$$` interface (full WireGuard handshake test, no traffic through main tunnel).
- Switches to first available peer.
- If `MASTER_PEER` is set, switches back to the master peer as soon as it recovers.

Probe interval: `MON_CHECK_INTERVAL` (default 10 s).

## UDP Obfuscation

AmneziaWG obfuscation params are passed to the WireGuard config:

| Param | Purpose |
|-------|---------|
| `Jc`, `Jmin`, `Jmax` | Junk packet count and size range |
| `S1`, `S2`, `S3`, `S4` | Init/response packet size adjustments |
| `H1`–`H4` | Magic header values |
| `UDP_SIGNATURE` | Protocol signature (`SIP` / `DNS` / `QUIC` / `STUN-WEBRTC`) |

`UDP_SIGNATURE` injects a pre-built packet header to disguise traffic as the chosen protocol.

## 3proxy Integration (client mode only)

When `PROXY_SOCKS5_ENABLED=true` or `PROXY_HTTP_ENABLED=true`, 3proxy is started after the VPN tunnel comes up, routing traffic through the VPN. Config is auto-generated unless `PROXY_CUSTOM_CONFIG=true` (then mount your own to `/etc/3proxy/3proxy.cfg`).

Ports (expose in docker-compose.yaml if needed):
- SOCKS5: `PROXY_SOCKS5_PORT` (default 4128)
- HTTP: `PROXY_HTTP_PORT` (default 3128)

## Prometheus Metrics

Enabled with `METRICS_ENABLED=true`. Two background processes start:

- `metrics/collector.sh` — polls `awg show all dump` every `METRICS_INTERVAL` seconds, writes Prometheus-format data to `/tmp/amneziawg/metrics.prom`. In server mode, peer-count metrics (`wg_server_peers_total`, `wg_server_peers_active`, `wg_server_peers_stale`) are computed inline inside the per-peer loop of that single `awg show all dump` call.
- `metrics/server.sh` — serves metrics on `METRICS_PORT` (default 9586) at `/metrics`

Key metrics exposed:
- `wg_interface_up` — interface operational status
- `wg_peer_last_handshake_timestamp_seconds` — last handshake per peer
- `wg_peer_handshake_age_seconds` — seconds since last handshake
- Transfer bytes (rx/tx) per peer
- Active peer and tunnel state (client mode)

Dashboard: `prometheus/wireguard_dashboard.json` (Grafana-compatible).
Alerts: `prometheus/wireguard_alerts.yaml`.

## Log Rotation

`logrotate.sh` runs every `LOGROTATE_INTERVAL` seconds (default 86400 = 24 h), keeping `LOGROTATE_ROTATE` rotated files and deleting files older than `LOGROTATE_MAXAGE` days.

Logs location: `./logs/amneziawg.log`, `./logs/3proxy/`.

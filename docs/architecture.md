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
| 1 | Unhealthy — config missing or not listening |
| 2 | `wg0` interface absent, or zombie state: interface exists but the `amneziawg-go` daemon is dead (e.g. OOM kill) or its UAPI socket is gone |

On any non-zero code the monitor calls `revive_wg_iface()` for an **in-place revival**: stop leftover daemon (SIGTERM → SIGKILL), remove the stale interface and UAPI socket (`/var/run/amneziawg/wg0.sock`), restart `amneziawg-go` with a PID file, re-apply address/`awg setconf`/link-up, and verify the daemon is listening again. iptables rules are kernel-level and survive daemon death, so they are not re-applied.

Revival is **continuous and unbounded**: the monitor retries every `MON_CHECK_INTERVAL` seconds forever and never restarts or kills the container. A crash of the daemon (including OOM kill with a stale UAPI socket left behind) is fully self-healed in place.

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

Before the health check, the monitor verifies the `amneziawg-go` daemon itself is alive (PID file + UAPI socket). If the daemon crashed (OOM kill, stale socket), it is revived in place with `revive_wg_iface()` and the active peer config is re-applied — same continuous-retry semantics as server mode, no container restart.

## UDP Obfuscation

AmneziaWG obfuscation params are passed to the WireGuard config:

| Param | Purpose |
|-------|---------|
| `Jc`, `Jmin`, `Jmax` | Junk packet count and size range |
| `S1`, `S2`, `S3`, `S4` | Init/response packet size adjustments |
| `H1`–`H4` | Magic header values |
| `UDP_SIGNATURE` | Protocol signature (`SIP` / `DNS` / `QUIC` / `STUN-WEBRTC`) |

`UDP_SIGNATURE` injects a pre-built packet header to disguise traffic as the chosen protocol.

### AmneziaWG 3.1 obfuscation (opt-in)

The image is built from AmneziaWG **3.1** (core `amneziawg-go` v3.1.20260828, tools v3.1.20260812). On top of the 2.x junk/size/header params, 3.1 adds statistical-analysis resistance. All new params are optional (empty = disabled, 2.x-compatible):

| Param | Side | Purpose |
|-------|------|---------|
| `HeaderProtectionKey` | server + peers | ChaCha20 encryption of packet header service fields; nonce from the first 12 bytes of the S-prefix → **requires S1–S4 ≥ 12**. With it enabled, leave H1–H4 at standard values `1`/`2`/`3`/`4`. |
| `ContentPaddingAddition` | peers | Random padding added to the transport payload |
| `RekeyAfterTime` / `RekeyTimeout` / `RejectAfterTime` | peers | Randomized re-handshake / handshake-timeout / forced-rekey intervals (seconds) |
| `KeepaliveTimeout` / `MaxHandshakeAttempts` | peers | Randomized keepalive interval and handshake retry count |
| `RandomTrailers` | server + peers | Random trailing bytes on packets |
| `DisableCookies` | server + peers | Suppress Cookie Reply packets |

All range params accept a fixed value (`a`) or a range (`a-b`); the daemon picks a random value from the range per packet/interval. Server-side params are written to both `wg0.conf` and every generated peer config; client-side params go into generated peer configs only. See [configuration.md](configuration.md).

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

See [`prometheus/`](../prometheus/) for the Grafana dashboard, alert rules, and scrape job example.

## Log Rotation

`logrotate.sh` runs every `LOGROTATE_INTERVAL` seconds (default 86400 = 24 h), keeping `LOGROTATE_ROTATE` rotated files and deleting files older than `LOGROTATE_MAXAGE` days.

Logs location: `./logs/amneziawg.log`, `./logs/3proxy/`.

# AmneziaWG - Docker Compose

Automation for running **AmneziaWG** using Docker Compose. The project aims to reduce the time spent deploying and maintaining WG tunnels. It is built from sources of [amneziawg-go](https://github.com/amnezia-vpn/amneziawg-go.git) and [amneziawg-tools](https://github.com/amnezia-vpn/amneziawg-tools.git) on latest alpine as base.

# Features

* One-command installation and launch
* Simple configuration via a `.env` file
* Supports both "server" and "client" modes
* Support for AmneziaWG protocol versions 2.0 and **3.1** (opt-in)
* Automatic peer configuration and generation of client configuration files
* Transparent [3proxy](https://3proxy.ru/) proxy for routing requests through the container in client mode (HTTP(S)/SOCKS5)
* Monitoring and automatic failover between peers if a tunnel fails
* **Continuous in-place crash revival** — if the `amneziawg-go` daemon dies (e.g. OOM kill), the monitor revives it without restarting the container
* Prometheus metrics exporter with Grafana dashboard, alert rules, and scrape job example

# Usage

## Basic Installation

> Tested on Ubuntu 24 / Debian 12.
> The script must be run **as root** or via `sudo`.

### 1️⃣ Clone the repository

```bash
git clone https://github.com/illmouse/amneziawg-go-docker-compose.git
cd amneziawg-go-docker-compose
```

### 2️⃣ Run the automatic setup script

```bash
chmod +x setup.sh && sudo ./setup.sh
```

**The script will:**

* Install Docker and Docker Compose
* Configure system kernel parameters
* Add log rotation rules
* Prompt to choose installation mode: server (default) or client
* Create the `.env` file interactively
* Automatically start the AmneziaWG container

## Verify Installation

Check that the container is running:

```bash
docker ps
```

View server logs:

```bash
docker logs amneziawg -f
```

# Server Mode

The mode is determined by the variable `WG_MODE=server`.

In server mode, the container supports multiple incoming connections from peers. WireGuard interface and peer configurations are created for clients to connect.

Client configurations generated in server mode are located in `config/server_peers/`.

## Server Mode Variables

[Variable description](#variable-description)

```ini
WG_MODE=server
WG_IFACE=wg0
WG_PORT=13440
WG_ADDRESS=10.100.0.1/24
WG_PEER_COUNT=5
WG_ENDPOINT=<server-ip>

Jc=3
Jmin=20
Jmax=150
S1=70
S2=150
S3=25
S4=76
H1=300
H2=350
H3=400
H4=450
```

## Changing the Number of Peers

* Increasing `WG_PEER_COUNT` will add new peers in numerical order.
* Decreasing `WG_PEER_COUNT` will remove excess peers starting from the last. Their configuration files are archived, and entries are removed from the `config/config.json` database.

# Client Mode

The mode is determined by the variable `WG_MODE=client`.

In client mode, the container connects to a single peer with automatic failover to the next available peer if the current one is unavailable.

Peer configurations for connection are located in `config/client_peers/`.

## Client Mode Variables

[Variable description](#variable-description)

```ini
WG_MODE=client
MASTER_PEER=peer1.conf

PROXY_SOCKS5_ENABLED=true
PROXY_SOCKS5_PORT="4128"
PROXY_SOCKS5_AUTH_ENABLED=false

PROXY_HTTP_ENABLED=false
PROXY_HTTP_PORT="3128"
PROXY_HTTP_AUTH_ENABLED=false

PROXY_CUSTOM_CONFIG=false
```

## Using protocol version 2.0

In client mode, the use of obfuscation via the UDP protocol is enabled by default. If parameters I1–I5 are not specified in the peer configuration, the QUIC obfuscation protocol is selected automatically and parameters I2–I5 are generated automatically.

In the .env file, you can specify one of the predefined UDP protocols using the `UDP_SIGNATURE` parameter. The available values are listed in the [variables description](#variable-description)

## AmneziaWG 3.1 obfuscation (optional)

The image is built from AmneziaWG **3.1**, which adds resistance to statistical DPI analysis. The 3.1 parameters are **opt-in** — with them unset, configs are generated exactly as in 2.x and existing clients keep working.

Enable via the setup wizard (answer "y" to the 3.1 profile) or set them in `.env`:

```ini
# 32-byte base64 key; encrypts packet headers. REQUIRES S1-S4 >= 12.
# With it enabled, keep H1-H4 at standard values 1/2/3/4.
HeaderProtectionKey=<base64 32-byte key>
ContentPaddingAddition=16-64
RekeyAfterTime=3000-4000
RekeyTimeout=5-10
RejectAfterTime=9000-10000
KeepaliveTimeout=8-15
MaxHandshakeAttempts=15
RandomTrailers=on
#DisableCookies=off
```

Range values (`a-b`) are randomized by the daemon per packet/interval. After enabling, re-download peer configs from `config/server_peers/` — clients need an **AmneziaWG 3.1-capable app**. Full parameter reference: [docs.amnezia.org](https://docs.amnezia.org/documentation/amnezia-wg/).

Generated S values stay within **12-20**, so packets never exceed a 1500-byte path MTU (a worst-case data packet is `1480 + S4` bytes outer). For constrained paths (PPPoE, IPv6 outer, nested tunnels) use the optional `WG_MTU` variable to lower the tunnel MTU.

Wizard timings produce long sessions: rekey at 50-67 min, session cap ~2.5-2.8 h — handshakes are rare and randomized, so handshake-age is a coarse liveness signal; the peer staleness threshold (`PEER_HANDSHAKE_TIMEOUT`) auto-scales to the rekey interval (in client mode it is derived from the active session config, since the client's `.env` carries no timing vars) so `wg_peers_active` / `wg_peers_stale` stay meaningful, and the rx-activity metrics (`wg_peers_rx_active` / `wg_peers_rx_idle`) give the most precise signal. Timing params are written to the server config as well as peer configs — the effective session lifetime is the minimum of both ends' `RejectAfterTime`.

# Internal Monitoring

Monitoring logs are saved in `logs/amneziawg.log`.

The monitoring script checks tunnel availability by pinging the `MON_CHECK_IP` target list (default `1.1.1.1,9.9.9.9,8.8.8.8`) — the tunnel counts as healthy when any target answers, so a single dead or rate-limiting target cannot fail a healthy tunnel.

* In **server mode**, health checks run on a fixed interval without peer switching. If the `amneziawg-go` daemon dies (e.g. OOM kill), the monitor revives it **in place** — continuously retrying, never restarting the container.
* In **client mode**, smart probe-based failover is used (see below), with the same in-place daemon revival.

## Client Mode Failover

When the tunnel health check fails, the monitor does **not** blindly switch to the next peer — and it does not switch on a single failed check either. A transient ping blip used to trigger an immediate failover (with a full tunnel rebuild and 3proxy restart, dropping all client connections); now failures must accumulate first.

**Failover flow:**

1. Failed health checks are counted. After `MON_FAIL_THRESHOLD` consecutive failures (default 3) the monitor starts probing peers.
2. The debounce is bypassed immediately when the current peer's rx counter shows a dead session (no received traffic since the failures began — keepalives deliver traffic at least every ~25 s on a live session).
3. Each candidate peer is probed through a temporary WireGuard interface: a successful handshake proves the server is up, the daemon is running, and the keys are valid; then a **data-path ping** through the probe interface proves traffic actually flows. A handshake alone is not enough — a server with broken forwarding still answers handshakes.
4. The first peer whose probe passes is switched to.
5. If no peers respond, the current tunnel health check is re-run. If it recovers, the monitor stays on the current peer and no switch is made.
6. If the tunnel is still down, the process repeats after `MON_CHECK_INTERVAL` seconds.

The probe handshake and data-path timeouts are controlled by `MON_CHECK_TIMEOUT`; the debounce threshold by `MON_FAIL_THRESHOLD`.

## Master Peer

If the `MASTER_PEER` variable is set:

* At container start in client mode, the specified peer is always activated first instead of the first one alphabetically.
* While on a backup peer, the master is **probed** (handshake + data-path check) before switching back, but no earlier than `MON_SWITCHBACK_DELAY` seconds (default 60) after the failover. This dwell prevents flap loops when the master passes quick probes but cannot sustain traffic.
* If the master probe fails, the dwell is extended and the active backup connection is not disrupted.
* Once the master probe succeeds, the tunnel switches back to it.

# Logs

Logs are stored in:

```ini
logs/
logs/3proxy/
```

Log rotation runs inside the container and is configured via the `LOGROTATE_*` variables.

# Full Configuration Reset

For a full reset:

```bash
rm -rf config/*
docker compose down -v
sudo ./setup.sh
```

This will recreate:

* Server keys
* Peer configurations
* Database
* `.env`

## Monitoring

The container exposes a Prometheus metrics endpoint (port `9586` by default, enable with `METRICS_ENABLE=true`).

Ready-to-use files are in [`prometheus/`](prometheus/):

| File | Description |
|------|-------------|
| [`wireguard_dashboard.json`](prometheus/wireguard_dashboard.json) | Grafana dashboard — works for both server and client modes, compatible with Grafana 9+ |
| [`wireguard_alerts.yaml`](prometheus/wireguard_alerts.yaml) | Prometheus alert rules for tunnel health, rx-based peer liveness, and throughput |
| [`wireguard_scrape_job.yaml`](prometheus/wireguard_scrape_job.yaml) | Example Prometheus scrape job configuration |

Import the dashboard via Grafana → Dashboards → Import. Uncomment the metrics port in `docker-compose.yml` to expose it outside the container.

# Variable Description

| Variable Name | Allowed Values | Default Value | Description |
| --- | --- | --- | --- |
| WG_MODE | `server`, `client` | `server` | Container run mode |
| WG_IFACE | any valid interface name | `wg0` | WireGuard interface name inside the container |
| WG_PORT | 1–65535 | `13440` | Port where WireGuard will be available on the host |
| WG_ADDRESS | any valid IP/subnet | `10.100.0.1/24` | WireGuard network address. Peers get /32 by default |
| WG_PEER_COUNT | integer ≥ 1 | `1` | Number of peers to generate configurations for |
| WG_ENDPOINT | any valid IP | `<server IP>` (auto-detected) | Host IP used for generating client configs. Peers connect to this IP |
| WG_MTU | integer ≥ 576 | _(empty = `1420`)_ | Optional tunnel MTU override. Lower for constrained paths (PPPoE, IPv6 outer, nested tunnels); data packets are `1480 + S4` bytes outer |
| Obfuscation parameters (`Jc`, `Jmin`, `Jmax`, `S1`, `S2`, `S3`, `S4`, `H1`, `H2`, `H3`, `H4`) | [parameter description](https://docs.amnezia.org/documentation/amnezia-wg/#how-it-works) | auto-generated by `setup.sh` | |
| AmneziaWG 3.1 parameters (`HeaderProtectionKey`, `ContentPaddingAddition`, `RekeyAfterTime`, `RekeyTimeout`, `RejectAfterTime`, `KeepaliveTimeout`, `MaxHandshakeAttempts`, `RandomTrailers`, `DisableCookies`) | [parameter description](https://docs.amnezia.org/documentation/amnezia-wg/) | _(empty = disabled)_ | Optional 3.1 obfuscation. `HeaderProtectionKey` is a base64 32-byte key requiring `S1`–`S4` ≥ 12; range params accept `a` or `a-b`; toggles accept `on`/`off`. Require 3.1-capable client apps when enabled |
| MASTER_PEER | peer configuration filename | none | Name of the main peer config in `config/client_peers/`. If not set, the first alphabetically is chosen |
| UDP_SIGNATURE | SIP, DNS, QUIC, STUN-WEBRTC | QUIC | UDP protocol code that will be used for connection obfuscation. The SIP code uses a VoIP signature from https://voidwaifu.github.io/Special-Junk-Packet-List/ |
| PROXY_SOCKS5_ENABLED | `true`, `false` | `false` | Enable SOCKS5 proxy in client mode |
| PROXY_SOCKS5_PORT | 1–65535 | `4128` | Port on which SOCKS5 proxy will run |
| PROXY_SOCKS5_AUTH_ENABLED | `true`, `false` | `false` | Enables basic auth for SOCKS5 proxy |
| PROXY_SOCKS5_AUTH_USER | `string` | `` | Username for SOCKS5 proxt |
| PROXY_SOCKS5_AUTH_PASSWORD | `string` | `` | Password for SOCKS5 proxy |
| PROXY_HTTP_ENABLED | `true`, `false` | `false` | Enable HTTP proxy in client mode |
| PROXY_HTTP_PORT | 1–65535 | `3128` | Port on which HTTP proxy will run |
| PROXY_HTTP_AUTH_ENABLED | `true`, `false` | `false` | Enables basic auth for HTTP proxy |
| PROXY_HTTP_AUTH_USER | `string`  | `` | Username for HTTP proxt |
| PROXY_HTTP_AUTH_PASSWORD | `string`  | `` | Password for HTTP proxy |
| PROXY_CUSTOM_CONFIG | `true`, `false` | `false` | Disables managed config for 3proxy. You can mount your own config to /etc/3proxy/3proxy.cfg |
| LOG_LEVEL | `ERROR`, `INFO`, `WARN`, `DEBUG` | `INFO` | Logging verbosity level |
| MON_CHECK_IP | comma-separated IP list | `1.1.1.1,9.9.9.9,8.8.8.8` | Ping targets for tunnel health checks, tried in order; the check passes when any target answers |
| MON_CHECK_INTERVAL | integer ≥ 1 | `10` | Interval in seconds between monitoring checks |
| MON_CHECK_TIMEOUT | integer ≥ 1 | `10` | Timeout in seconds for health check pings and peer handshake probes |
| MON_PING_COUNT | integer ≥ 1 | `3` | Ping packets sent to the first (primary) health-check target. The check passes if any packet gets a response (client mode) |
| MON_FALLBACK_PING_COUNT | integer ≥ 1 | `1` | Ping packets sent to health-check targets after the first; keeps the worst-case dead-tunnel check fast |
| MON_FAIL_THRESHOLD | integer ≥ 1 | `3` | Client mode: consecutive failed health checks before peer probing/failover starts (debounce against transient blips). Bypassed immediately when the current peer's rx counter shows a dead session. `1` = switch on first failure (pre-5.0.7 behavior) |
| MON_SWITCHBACK_DELAY | integer ≥ 0 | `60` | Client mode: minimum seconds on a backup peer before the master is probed for switchback. Prevents failover/switchback flap loops when the master answers handshakes but cannot carry traffic. `0` = probe as soon as the tunnel is healthy |
| LOGROTATE_INTERVAL | integer ≥ 1 | `86400` | Seconds between log rotation runs inside the container (default: 24 h) |
| LOGROTATE_ROTATE | integer ≥ 0 | `1` | Number of rotated log files to keep (1 = keep only the previous log) |
| LOGROTATE_MAXAGE | integer ≥ 1 | `1` | Delete rotated log files older than this many days |
| METRICS_ENABLED | `true`, `false` | `false` | Enable Prometheus metrics endpoint |
| METRICS_PORT | 1–65535 | `9586` | Port to expose the `/metrics` endpoint on |
| METRICS_INTERVAL | integer ≥ 1 | `15` | Seconds between metrics collection runs |
| PEER_HANDSHAKE_TIMEOUT | integer ≥ 1 | `180` (auto-scaled with 3.1, max `7200`) | Seconds since last handshake before a peer is considered disconnected (server mode); auto-derived from the 3.1 `RekeyAfterTime` when set and not pinned explicitly — in client mode the timings are read from the active session config, since the `.env` timing vars are empty there by design. For the most precise liveness prefer rx-activity metrics (wg_peers_rx_active / wg_peers_rx_idle) |
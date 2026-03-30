# AmneziaWG - Docker Compose

Automation for running **AmneziaWG** using Docker Compose. The project aims to reduce the time spent deploying and maintaining WG tunnels. It is built from sources of [amneziawg-go](https://github.com/amnezia-vpn/amneziawg-go.git) and [amneziawg-tools](https://github.com/amnezia-vpn/amneziawg-tools.git) on latest alpine as base.

# Features

* One-command installation and launch
* Simple configuration via a `.env` file
* Supports both "server" and "client" modes
* Support for AmneziaWG protocol version 2.0
* Automatic peer configuration and generation of client configuration files
* Transparent [3proxy](https://3proxy.ru/) proxy for routing requests through the container in client mode (HTTP(S)/SOCKS5)
* Monitoring and automatic failover between peers if a tunnel fails

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

In client mode, the use of obfuscation via the UDP protocol is enabled by default. If parameters I1–I5 are not specified in the peer configuration, the DEFAULT obfuscation protocol is selected automatically and parameters I2–I5 are generated automatically.

In the .env file, you can specify one of the predefined UDP protocols using the `UDP_SIGNATURE` parameter. The available values are listed in the [variables description](#variable-description)

# Internal Monitoring

Monitoring logs are saved in `logs/amneziawg.log`.

The monitoring script checks tunnel availability via ping to `MON_CHECK_IP` (default `9.9.9.9`).

* In **server mode**, health checks run on a fixed interval without peer switching.
* In **client mode**, smart probe-based failover is used (see below).

## Client Mode Failover

When the tunnel health check fails, the monitor does **not** blindly switch to the next peer. Instead it probes each candidate peer by spinning up a temporary WireGuard interface and waiting for a successful handshake. A handshake proves the server is up, the WireGuard daemon is running, and the keys are valid end-to-end — unlike a simple ping to the endpoint IP, which only verifies host reachability.

**Failover flow:**

1. Current peer is marked as failed.
2. All peers are probed in rotation order (including the current one, which may have self-healed).
3. The first peer whose handshake succeeds is switched to immediately.
4. If no peers respond, the current tunnel health check is re-run. If it recovers, the monitor stays on the current peer and no switch is made.
5. If the tunnel is still down, the process repeats after `MON_CHECK_INTERVAL` seconds.

The probe handshake timeout is controlled by `MON_CHECK_TIMEOUT`.

## Master Peer

If the `MASTER_PEER` variable is set:

* At container start in client mode, the specified peer is always activated first instead of the first one alphabetically.
* While on a backup peer and the master's failure cooldown has expired, the master peer is **probed** (temporary interface + handshake check) before switching back. If the probe fails, the cooldown is extended and the active backup connection is not disrupted.
* Once the master peer probe succeeds, the tunnel switches back to it.

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

# Variable Description

| Variable Name | Allowed Values | Default Value | Description |
| --- | --- | --- | --- |
| WG_MODE | `server`, `client` | `server` | Container run mode |
| WG_IFACE | any valid interface name | `wg0` | WireGuard interface name inside the container |
| WG_PORT | 1–65535 | `13440` | Port where WireGuard will be available on the host |
| WG_ADDRESS | any valid IP/subnet | `10.100.0.1/24` | WireGuard network address. Peers get /32 by default |
| WG_PEER_COUNT | integer ≥ 1 | `1` | Number of peers to generate configurations for |
| WG_ENDPOINT | any valid IP | `<server IP>` (auto-detected) | Host IP used for generating client configs. Peers connect to this IP |
| Obfuscation parameters (`Jc`, `Jmin`, `Jmax`, `S1`, `S2`, `S3`, `S4`, `H1`, `H2`, `H3`, `H4`) | [parameter description](https://docs.amnezia.org/documentation/amnezia-wg/#how-it-works) | auto-generated by `setup.sh` | |
| MASTER_PEER | peer configuration filename | none | Name of the main peer config in `config/client_peers/`. If not set, the first alphabetically is chosen |
| UDP_SIGNATURE | DEFAULT, DNS, QUIC | DEFAULT | UDP protocol code that will be used for connection obfuscation. The DEFAULT code uses a VoIP signature from https://voidwaifu.github.io/Special-Junk-Packet-List/ |
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
| MON_CHECK_IP | any valid IP | `9.9.9.9` | IP address used for tunnel health check pings |
| MON_CHECK_INTERVAL | integer ≥ 1 | `10` | Interval in seconds between monitoring checks |
| MON_CHECK_TIMEOUT | integer ≥ 1 | `10` | Timeout in seconds for health check pings and peer handshake probes |
| MON_PEER_FAIL_COOLDOWN | integer ≥ 0 | `300` | Seconds a failed peer stays excluded from rotation before being retried |
| LOGROTATE_INTERVAL | integer ≥ 1 | `86400` | Seconds between log rotation runs inside the container (default: 24 h) |
| LOGROTATE_ROTATE | integer ≥ 0 | `1` | Number of rotated log files to keep (1 = keep only the previous log) |
| LOGROTATE_MAXAGE | integer ≥ 1 | `1` | Delete rotated log files older than this many days |
| METRICS_ENABLED | `true`, `false` | `false` | Enable Prometheus metrics endpoint |
| METRICS_PORT | 1–65535 | `9586` | Port to expose the `/metrics` endpoint on |
| METRICS_INTERVAL | integer ≥ 1 | `15` | Seconds between metrics collection runs |
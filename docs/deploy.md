# Deploy

## Prerequisites

- Linux host with kernel module support for WireGuard/TUN
- Docker and Docker Compose (installed by `setup.sh` if absent)
- Root or sudo access for setup

## Quick Start

```bash
sudo ./setup.sh
```

`setup.sh` performs these steps:

1. Installs Docker and Docker Compose (`scripts/install-docker.sh`) if not present
2. Configures system settings — IP forwarding, kernel params (`scripts/configure-system.sh`)
3. Prompts to create/overwrite `.env` via interactive wizard (`scripts/create-env-file.sh`)
4. Uncomments proxy ports in `docker-compose.yaml` if proxy is enabled
5. Optionally starts services with `docker compose up -d`

After setup, start manually if needed:

```bash
docker compose up -d
docker compose logs -f
```

## Manual Setup

```bash
cp .env.example .env
# Edit .env: set WG_ENDPOINT, WG_MODE, peer count, etc.
docker compose up -d
docker compose logs -f
```

## Server Mode

1. Set `WG_MODE=server`, `WG_ENDPOINT=<your-public-ip>`, `WG_PEER_COUNT=<n>` in `.env`
2. Start: `docker compose up -d`
3. Peer configs are generated at `config/server_peers/peer1.conf`, `peer2.conf`, ...
4. Distribute peer configs (or QR code PNGs) to clients

## Client Mode

1. Place peer `.conf` files in `config/client_peers/`
2. Set `WG_MODE=client` in `.env`
3. Optionally set `MASTER_PEER=peer1.conf` for preferred failover target
4. Enable proxy if needed: `PROXY_SOCKS5_ENABLED=true` and uncomment proxy port in `docker-compose.yaml`
5. Start: `docker compose up -d`

## Expose Proxy / Metrics Ports

Edit `docker-compose.yaml` and uncomment the desired lines:

```yaml
ports:
  - ${PROXY_SOCKS5_PORT}:${PROXY_SOCKS5_PORT}/tcp
  - ${PROXY_HTTP_PORT}:${PROXY_HTTP_PORT}/tcp
  - ${METRICS_PORT}:${METRICS_PORT}/tcp
  - ${WG_PORT}:${WG_PORT}/udp
```

### Prometheus Monitoring

1. Set `METRICS_ENABLE=true` in `.env`
2. Uncomment the metrics port (`9586`) in `docker-compose.yml`
3. Add the scrape job from [`prometheus/wireguard_scrape_job.yaml`](../prometheus/wireguard_scrape_job.yaml) to your Prometheus config
4. Import [`prometheus/wireguard_combined_dashboard.json`](../prometheus/wireguard_combined_dashboard.json) into Grafana
5. Optionally load [`prometheus/wireguard_alerts.yaml`](../prometheus/wireguard_alerts.yaml) as a Prometheus alert rule file

## Log Rotation (host-side)

An example logrotate config is provided at `amneziawg.logrotate.example`. Copy and adapt it for host-level rotation of `./logs/`.

## Full Reset

Stop and remove everything, then re-run setup:

```bash
docker compose down
rm -rf config/ logs/
# Optionally remove .env to reconfigure from scratch
rm -f .env
sudo ./setup.sh
```

> Warning: `rm -rf config/` deletes all keys and peer configs. Clients will need new configs.

## Upgrade

```bash
docker compose pull
docker compose up -d
```

The container is stateless for keys/configs (all in `./config/`), so pull-and-restart is safe. Existing peer configs are preserved.

### Upgrading to v5.0.0b (AmneziaWG 3.1)

v5.0.0b upgrades the bundled AmneziaWG core to **3.1** (amneziawg-go v3.1.20260828, tools v3.1.20260812). Notes:

- **Breaking:** generated peer configs now include the previously missing `I5` obfuscation parameter. Existing peer configs on disk are **not** touched by the upgrade; they keep working. New peer configs (fresh generation or peer count changes) gain `I5` — old AmneziaWG 2.x client apps may reject it, so distribute new configs together with an updated client app.
- **3.1 obfuscation params are opt-in.** With the new variables unset, server and peer configs are generated exactly as before (except `I5`) and 2.x clients keep connecting.
- To enable 3.1 obfuscation (Header Protection, content padding, randomized timings, random trailers): re-run the setup wizard (`sudo ./setup.sh`, answer "y" to the 3.1 profile) or set the variables from `.env.example` manually. Then re-download and redistribute peer configs from `config/server_peers/` — clients need an **AmneziaWG 3.1-capable app** (3.1 params in configs are ignored/rejected by older apps).
- The crash-revival rework means the monitor now self-heals a dead daemon (e.g. after an OOM kill, including stale UAPI socket) in place, continuously, instead of restarting the container after 3 failures. No action needed — behavior change is only visible in logs.

### Upgrading to v5.0.1b

v5.0.0b wizard users with **slow tunnels** should upgrade:

1. Re-run the wizard (`sudo ./setup.sh`, answer "y" to the 3.1 profile) so `S1`–`S4` are regenerated within **12–20** — or edit `.env` by hand so `S1`–`S4` ≤ 20 (values above 20 made every full-size data packet, `1480 + S4` bytes, exceed a 1500-byte path MTU and fragment, causing severe throughput degradation).
2. Recreate containers on **both server and client** (`docker compose up -d --force-recreate` or `docker compose pull && docker compose up -d`).
3. Redistribute peer configs from `config/server_peers/` to all clients.

For constrained paths (PPPoE 1492, IPv6 outer, nested tunnels) the new optional `WG_MTU` env var can lower the tunnel MTU (e.g. `WG_MTU=1360`) — set it on both server and clients.

### Upgrading to v5.0.2

Wizard 3.1 profile now generates `RejectAfterTime=9000-10000` (was 180-190) — long randomized sessions; handshakes now occur every ~50-67 min, which is expected. Monitoring based on handshake age must switch to rx-activity metrics (`wg_peers_rx_active` / `wg_peers_rx_idle`) or transfer counters.

To apply: re-run the wizard (`sudo ./setup.sh`, answer "y" to the 3.1 profile), recreate containers (`docker compose pull && docker compose up -d`), and redistribute peer configs.

### Upgrading to v5.0.3

Server timing fix: the server's `wg0.conf` now also receives the 3.1 timing params (`RekeyAfterTime`, `RekeyTimeout`, `RejectAfterTime`, `KeepaliveTimeout`, `MaxHandshakeAttempts`) and `ContentPaddingAddition` when set. Previously the server ran its built-in default `RejectAfterTime=180s`, silently capping sessions at ~3 minutes regardless of the longer client-side values.

To apply: recreate the server container (`docker compose pull && docker compose up -d`) — the config regenerates automatically. Peer config content is unchanged, but redistributing them is harmless. Old (vanilla-default) clients are unaffected: they keep their own rekey cadence.

### Upgrading to v5.0.4

Two 3.1 session-timing fixes. No config format change and no peer config regeneration — both ends can be upgraded independently.

- `PEER_HANDSHAKE_TIMEOUT` now auto-scales to the configured 3.1 `RekeyAfterTime` (capped at 7200 s), so `wg_peers_active` / `wg_peers_stale` no longer report healthy long-lived peers as stale between rekeys. The legacy 180 s default is unchanged when 3.1 timings are not set. Set `PEER_HANDSHAKE_TIMEOUT` explicitly to pin the value.
- The client monitor's "is the current peer still alive?" check now uses rx traffic growth instead of handshake age. Previously a transient ping failure against a healthy 3.1 session (whose last handshake could be 50-67 min old) caused a spurious failover to a backup peer.

Alerting on handshake age still works, but `wg_peers_rx_active` / `wg_peers_rx_idle` remain the more precise liveness signal. If you already migrated your alerts to the rx-based metrics in v5.0.2, no action is needed.

To apply: recreate the server and client containers (`docker compose pull && docker compose up -d`).

### Upgrading to v5.0.5

Monitoring fixes for AmneziaWG 3.1 long session timings. No config format change and no peer config regeneration — upgrade each end independently.

- Fixed the v5.0.4 `wg_peers_stale` bug: the setup wizard writes 3.1 timings as ranges (`RekeyAfterTime=3000-4000`), which bash arithmetic read as subtraction, producing a negative staleness threshold and marking every peer stale. The threshold now takes the upper bound of each range and adds the rekey retry window.
- Handshake-age alerts (`WireGuardHandshakeStale` / `WireGuardHandshakeAgeing`) fired permanently under 3.1 (healthy sessions go 50-67 min between handshakes). They are replaced by the rx-based `WireGuardPeerUnreachable` alert, which triggers when a connected peer stops receiving traffic.
- Alert severity `critical` was renamed to `high` — update notification routing if you matched on the old label value.
- Dashboard handshake panels no longer use hardcoded 180 s red thresholds; new "Peers RX Active" / "Peers RX Idle" panels show handshake-independent liveness.

To apply: recreate the containers (`docker compose pull && docker compose up -d`), re-import `prometheus/wireguard_dashboard.json` and reload the `prometheus/wireguard_alerts.yaml` rules in Prometheus if you use the bundled files.

### Upgrading to v5.0.6

Client-mode fix for the peer staleness metrics. No config format change and no peer config regeneration — upgrade each end independently.

- In client mode `wg_peers_active` / `wg_peers_stale` still used the fixed 180 s threshold after v5.0.5: the 3.1 timing params are empty in the client's `.env` by design (they are a server-wizard artifact), so the auto-scaling had no inputs. The threshold is now also derived from the active session config (`/etc/amneziawg/wg0.conf`), where the timings actually live in client mode. Precedence: explicit `PEER_HANDSHAKE_TIMEOUT` > `.env` timing vars > session config > 180 s.

To apply: recreate the client containers (`docker compose pull && docker compose up -d`). Verify with `. /entrypoint/lib/env.sh; echo $PEER_HANDSHAKE_TIMEOUT` — with 3.1 timings it should exceed 180 (e.g. ~4000 for the wizard's `RekeyAfterTime=3000-4000`), after which `wg_peers_active` reports healthy long-lived sessions correctly.

## Useful Commands

```bash
# View logs
docker compose logs -f

# Check WireGuard peers inside container
docker compose exec awg awg show

# Restart only the container (not full reset)
docker compose restart awg

# Open shell inside container
docker compose exec awg sh
```

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

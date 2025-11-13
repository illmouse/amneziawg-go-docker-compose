# AmneziaWG Docker VPN

This repository contains a **Docker setup for AmneziaWG**, a VPN similar to WireGuard, using the `amneziavpn/amneziawg-go:0.2.15` container.  
Server and client configurations are generated dynamically, keys are managed automatically, making the system convenient and reusable.

---

## Features

- Automatically generates server and client keys on the first run.
- Dynamically generates server and client configurations based on environment variables.
- Client configuration (`peer.conf`) is ready to use.
- Logs are output to `docker logs`.
- Reusable: after generating keys and configs, the container simply starts the VPN without regenerating keys.

---

## Environment Variables (`.env`)

The `.env` file allows you to configure the container. Place it next to your `docker-compose.yml`.  
Example:

```bash
# .env

# Mandatory params
WG_ENDPOINT=                      # Public endpoint

# Optional default params
WG_IFACE=wg0                      # Name of the VPN interface inside the container
WG_ADDRESS=10.100.0.1/24          # Server IP and subnet
WG_CLIENT_ADDR=10.100.0.2/32      # Client IP
WG_PORT=13440                     # VPN port to accept connections

# AmneziaWG tunable parameters
Jc=3                           
Jmin=1
Jmax=50
S1=25
S2=72
H1=1411927821
H2=1212681123
H3=1327217326
H4=1515483925
````

**Notes:**

* Parameters `Jc`, `Jmin`, `Jmax`, `S1`, `S2`, `H1-H4` are critical for VPN operation. Do not change them unless necessary.

---

## How It Works

1. **First run:**

   * The container checks for keys and configs in `/etc/amneziawg` (mounted via Docker volume).
   * If anything is missing, it generates:

     * Server keys (`privatekey`, `publickey`, `presharedkey`)
     * Client key (`client_privatekey`)
     * Server config (`wg0.conf`)
     * Client config (`peer.conf`)
   * Sets permissions `600` for all keys.
   * Starts the VPN interface (`WG_IFACE`) and applies NAT/iptables through it.

2. **Subsequent runs:**

   * The container finds existing keys/configs and skips key generation.
   * A new configuration is generated using the existing keys or new ones if missing.
   * The new configuration is compared with the existing one and replaced if they differ.
   * Starts the VPN and applies NAT/iptables.
   * Logs are available via `docker logs`.

3. **Client configuration:**

   * Available at `/etc/amneziawg/peer.conf`.
   * Can be copied to the client device for connection.

---

## Docker Compose Example

```yaml
services:
  amneziawg:
    image: amneziavpn/amneziawg-go:0.2.15
    container_name: amneziawg
    env_file:
      - .env
    cap_add:
      - NET_ADMIN
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
    devices:
      - /dev/net/tun:/dev/net/tun
    ports:
      - ${WG_PORT}:${WG_PORT}/udp
    volumes:
      - ./config:/etc/amneziawg
      - ./logs:/var/log/amneziawg
      - ./entrypoint.sh:/entrypoint.sh:ro
    entrypoint: ["/entrypoint.sh"]
    restart: always
    networks:
      awg:

networks:
   awg:
```

**Notes:**

* `./config` is used to store keys and configurations.
* If the directory is empty, the container will automatically generate keys and configs.
* VPN traffic is NATed through the `WG_IFACE` interface.

---

## Usage

1. **Create a directory for configs:**

```bash
chmod +x entrypoint.sh
```

2. **Create a `.env` file** with the desired parameters.

3. **Start the container:**

```bash
docker-compose up -d
```

4. **View logs:**

```bash
docker logs -f amneziawg
```

5. **Retrieve client configuration:**

```bash
docker cp amneziawg:/etc/amneziawg/peer.conf ./peer.conf
```

Use `peer.conf` on the client device to connect to the VPN.

---

## Important Notes

* To fully regenerate the VPN configuration, you can delete the contents of `./config`. On the next start, the container will create new keys and configs.
* Make sure the UDP port (`WG_PORT`) is open on your router/firewall to allow client connections.

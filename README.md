# AmneziaWG Docker Compose VPN

This repository contains a **Docker setup for AmneziaWG** — a VPN similar to WireGuard, using the [amneziavpn/amneziawg-go](https://hub.docker.com/r/amneziavpn/amneziawg-go/tags) container.

Server and client configurations are created dynamically, keys are managed automatically via a JSON database, making the system convenient and reusable.

> [!NOTE]
> This configuration is designed to use the official container, so all settings for its operation are performed without rebuilding the container itself.

---

## 🎯 Features

- **Automatic key generation** for the server and clients on first start
- **JSON database** for storing all configurations and keys
- **Dynamic peer management** - peers can be added/removed without recreating the container
- **Modular architecture** - each setup stage is in a separate script
- **Colored logs with emojis** for convenient monitoring
- **Automatic permission fixing** for configuration files
- **Client configurations** are generated automatically in `./config/peers/`
- **Logs are output** to `docker logs` and also to `./logs/amneziawg.log`

---

## ⚙️ Environment Variables (`.env`)

```bash
# .env

# Public host address on which connections will be accepted
WG_ENDPOINT=

# Main WireGuard parameters
WG_IFACE=wg0
WG_ADDRESS=10.100.0.1/24
WG_PORT=13440
WG_PEER_COUNT=1

# AmneziaWG obfuscation parameters
Jc=3
Jmin=1
Jmax=50
S1=25
S2=72
H1=1411927821
H2=1212681123
H3=1327217326
H4=1515483925
```

**Notes:**
* Parameters `Jc`, `Jmin`, `Jmax`, `S1`, `S2`, `H1-H4` are important for the VPN operation. More details in the [documentation](https://docs.amnezia.org/documentation/amnezia-wg/#%D0%BF%D0%B0%D1%80%D0%B0%D0%BC%D0%B5%D1%82%D1%80%D1%8B-%D0%BA%D0%BE%D0%BD%D1%84%D0%B8%D0%B3%D1%83%D1%80%D0%B0%D1%86%D0%B8%D0%B8)

---

## 🚀 How it works when starting the container

### Container startup process:

1. **🔵 Environment Initialization** (`init.sh`)
   - Creating necessary directories
   - Setting environment variables
   - Checking dependencies (jq, awg)
   - Creating directory structure

2. **🗃️ Database Initialization** (`config-db.sh`)
   - Creating JSON database `config.json`
   - Writing initial server configuration
   - Updating parameters from environment variables

3. **🔑 Server Key Generation** (`server-keys.sh`)
   - Checking for existing keys in the database
   - Generating new keys if necessary
   - Saving keys to the database

4. **👤 Peer Management** (`peers.sh`)
   - Comparing current and desired peer count
   - Generating new peers if necessary
   - Creating keys and IP addresses for each peer

5. **⚙️ Configuration Generation** (`generate-configs.sh`)
   - Creating server configuration (`wg0.conf`)
   - Generating individual configurations for each peer
   - Comparing and updating only changed configs

6. **🔒 Permission Fixing** (`functions.sh`)
   - Setting `700` permissions for directories
   - Setting `600` permissions for all configuration files and keys
   - Logging permission changes

7. **🌐 WireGuard Startup** (`start-wireguard.sh`)
   - Starting the AmneziaWG interface
   - Applying configuration
   - Setting up iptables and NAT
   - Checking functionality

---

## 📊 Peer Management

1. **When decreasing `WG_PEER_COUNT`:**
   - Peers are **removed from the active configuration** (`wg0.conf`)
   - But **configurations are preserved** for potential future use in `./config/peers/`
   - Only the first N peers in alphanumeric order are kept (peer1, peer2, peer3...)

2. **When increasing `WG_PEER_COUNT`:**
   - The system first **fills gaps** in peer numbering
   - If peer1 and peer3 exist, but peer2 is missing - peer2 will be created
   - Then new sequential peers are added

3. **Work examples:**

**Scenario 1: Decreasing peer count**
```bash
# Was: WG_PEER_COUNT=3 (peer1, peer2, peer3 in configuration)
# Became: WG_PEER_COUNT=1
# Result: Only peer1 remains in wg0.conf, peer2 and peer3 remain in the DB
```

**Scenario 2: Increasing with gaps**
```bash
# In DB: peer1, peer3 (peer2 was manually deleted)
# WG_PEER_COUNT=3
# Result: peer2 will be created, then peer4 will NOT be created because only 3 peers are needed
```

**Scenario 3: Sequential addition**
```bash
# In DB: peer1, peer2
# WG_PEER_COUNT=4
# Result: peer3, peer4 will be created
```

### Manual peer management:

**Complete peer removal from the system:**
```bash
# Remove a peer from the DB and filesystem

# delete the peer from config/config.json
nano config/config.json

# Restart to apply changes
docker compose restart amneziawg
```

**Peer restoration:**
```bash
# Simply increase WG_PEER_COUNT - the system will fill gaps automatically
WG_PEER_COUNT=3
docker compose restart amneziawg
```

---

## 🗃️ Database Structure

```json
{
  "server": {
    "interface": "wg0",
    "address": "10.100.0.1/24",
    "port": 13440,
    "endpoint": "your-server-ip",
    "junk": {
      "jc": 3,
      "jmin": 1,
      "jmax": 50,
      "s1": 25,
      "s2": 72,
      "h1": 1411927821,
      "h2": 1212681123,
      "h3": 1327217326,
      "h4": 1515483925
    },
    "keys": {
      "private_key": "server_private_key_here",
      "public_key": "server_public_key_here"
    }
  },
  "peers": {
    "peer1": {
      "name": "peer1",
      "ip": "10.100.0.2/24",
      "private_key": "peer_private_key",
      "public_key": "peer_public_key",
      "preshared_key": "preshared_key",
      "created": "2024-01-15T10:30:00Z"
    },
    "peer2": {
      "...": "..."
    }
  },
  "meta": {
    "version": "1.0",
    "last_updated": "2024-01-15T10:30:00Z"
  }
}
```

---

## 🐳 Docker Compose Example

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
      - ./entrypoint:/entrypoint:ro
    entrypoint: ["/entrypoint/main.sh"]
    healthcheck:
      test: ["CMD", "sh", "-c", "ip link show wg0 && awg show wg0 2>/dev/null | grep -q listening"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    restart: always
    networks:
      awg:

networks:
   awg:
```

**Notes:**
* `./config` - stores all keys, configurations and the JSON database
* `./logs` - directory for application logs
* `./entrypoint` - modular initialization scripts
* `./scripts` - initialization scripts for `setup.sh` to work

---

## 📋 Usage

### Quick start:

```bash
# Make scripts executable
chmod +x setup.sh
chmod +x entrypoint/*.sh

# Run the setup script
./setup.sh

# Or run manually
docker compose up -d
```

### Getting client configurations:

Peer configurations are located in:
```
./config/peers/
├── peer1.conf
├── peer2.conf
└── peer3.conf
```

Each file contains a complete configuration for client connection.

### Viewing logs:

```bash
# Colored logs with emojis
docker logs amneziawg

# Or raw logs
tail -f ./logs/amneziawg.log
```

---

## 🛠️ Important Notes

### Security:
- All keys and configuration files automatically receive `600` permissions
- JSON database is protected from unauthorized access
- Permissions are checked and fixed on every startup

### Migration and backups:
- For full VPN regeneration, delete the `./config` directory
- To save configuration, copy `./config/config.json`
- To migrate to another server, transfer the entire `./config` directory

### Network settings:
- Ensure the UDP port (`WG_PORT`) is open on the router/firewall
- Verify that `WG_ENDPOINT` contains the correct public IP or domain name
- For NAT to work, ensure IP forwarding is enabled on the host

### Troubleshooting:
```bash
# Check interface status
docker exec amneziawg awg show wg0

# View initialization logs
docker logs amneziawg

# Check the database
docker exec amneziawg cat /etc/amneziawg/config.json | jq .
```

---

## 🔄 Update Process

When changing any parameters in the `.env` file:

1. **Server parameters** (port, endpoint, etc.) - automatically updated in the database
2. **Obfuscation parameters** - applied to all peers when regenerating configs
3. **Peer count** - dynamically managed without losing existing configurations
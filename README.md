# AmneziaWG Docker Compose VPN

This repository contains a **Docker setup for AmneziaWG** - a VPN similar to WireGuard, using the [amneziavpn/amneziawg-go](https://hub.docker.com/r/amneziavpn/amneziawg-go/tags) container.

Server and client configurations are created dynamically, keys are managed automatically, making the system convenient and reusable.

> [!NOTE]
> This configuration is designed to use the official container, so all settings for its operation are performed outside the container.

> [!IMPORTANT]
> The automatic configuration is designed to work with only one peer due to the specific nature of the task being solved.

---

## Features

- Automatic generation of server and client keys on first launch.
- Dynamic generation of server and client configurations based on environment variables.
- Client configuration (`./config/peer.conf`) is ready to use.
- Logs are output to `docker logs` as well as to `./logs/amneziawg.log`.
- Reusability: After generating keys and configs, the container simply runs the VPN without regenerating them.

---

## Environment Variables (`.env`)

```bash
# .env

# Optional parameters with default values
WG_IFACE=wg0                      # Name of the VPN interface inside the container
WG_ADDRESS=10.100.0.1/24          # Server IP and subnet
WG_CLIENT_ADDR=10.100.0.2/32      # Client IP
WG_PORT=13440                     # VPN port to accept connections
WG_ENDPOINT=                      # Public host address for accepting connections. Determined automatically via ifconfig.me

# Automatically generated variables
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

* The parameters `Jc`, `Jmin`, `Jmax`, `S1`, `S2`, `H1-H4` are important for the VPN operation. They will be randomly generated when the setup.sh script is first run. You can set your own. More details in the [documentation](https://docs.amnezia.org/documentation/amnezia-wg/#%D0%BF%D0%B0%D1%80%D0%B0%D0%BC%D0%B5%D1%82%D1%80%D1%8B-%D0%BA%D0%BE%D0%BD%D1%84%D0%B8%D0%B3%D1%83%D1%80%D0%B0%D1%86%D0%B8%D0%B8).

---

## How It Works

1. **First Launch:**

   * The container checks for keys and configs in `/etc/amneziawg`
   * If anything is missing, it generates:

     * Server keys (`privatekey`, `publickey`, `presharedkey`)
     * Client key (`client_privatekey`)
     * Server config (`wg0.conf`)
     * Client config (`peer.conf`)
   * Sets permissions to `600` for all keys.
   * Starts the VPN interface (`WG_IFACE`) and applies NAT/iptables through it.

2. **Subsequent Launches:**

   * The container finds existing keys/configs and skips key generation.
   * A new configuration is generated with the found keys or new ones are generated.
   * The new configuration is compared with the existing one and replaced if they differ.
   * Starts the VPN and applies NAT/iptables.

3. **Client Configuration:**

   * Available in `/etc/amneziawg/peer.conf`.
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

* `./config` is used to store keys and configurations. If the directory is empty, the container will automatically create keys and configs.
* `./logs` is used to store application logs.

---

## Usage

1. **Run the installation configuration script:**

```bash
chmod +x setup.sh && ./setup.sh
```

What the script does:
- Installs docker and docker compose if missing
- Enables IP forwarding in /etc/sysctl.conf
- Copies the monitoring script to /usr/local/bin/amneziawg-monitor.sh
- Adds a cron job to run the script in /etc/cron.d/amneziawg-monitor
- Checks the output of the monitoring script
- If the .env file is missing, it creates the file by automatically generating variables
- Outputs the configuration for setting up the client to the console

2. **Getting the client configuration:**

At the end of the script's execution, the configuration for setting up on the peer side is displayed.

The configuration file can be found at `./config/peer.conf`

Example script configuration output:
```bash
[SETUP] Starting AmneziaWG setup...
[SETUP] Checking Docker installation...
[SETUP] Docker and Docker Compose are already installed
[SETUP] Configuring IP forwarding in sysctl...
[SETUP] IP forwarding already enabled in sysctl.conf
[SETUP] Applying sysctl settings...
[SETUP] Sysctl settings applied successfully
[SETUP] IP forwarding is enabled (net.ipv4.ip_forward=1)
[SETUP] Creating .env file with generated obfuscation values
[SETUP] Generated obfuscation values:
[SETUP]   JC=3, JMIN=50, JMAX=1000
[SETUP]   S1=124, S2=52
[SETUP]   H1=7799, H2=16627, H3=7319, H4=10232
[WARNING] WG_ENDPOINT is not set or empty in .env file
[SETUP] Detecting public IP address...
[SETUP] Detected public IP: <external_ip>
[SETUP] WG_ENDPOINT has been set to: <external_ip>
[SETUP] Copying amneziawg-monitor.sh to /usr/local/bin/
[SETUP] Copying amneziawg-monitor to /etc/cron.d/
[SETUP] Making entrypoint.sh executable
[SETUP] Starting Docker Compose from current directory
[+] Running 1/1
 ✔ Container amneziawg  Started                                                                            11.4s 
[SETUP] Waiting for container to initialize...
[SETUP] Testing monitor script...
amneziawg
[SETUP] Monitor script executed successfully
[SETUP] Checking container status...
CONTAINER ID   IMAGE                            COMMAND            CREATED          STATUS                                     PORTS                                             NAMES
1a7a42d203ac   amneziavpn/amneziawg-go:0.2.15   "/entrypoint.sh"   34 seconds ago   Up Less than a second (health: starting)   0.0.0.0:13440->13440/udp, [::]:13440->13440/udp   amneziawg
[SETUP] Setup complete!
[SETUP] - IP forwarding configured in /etc/sysctl.conf
[SETUP] - Monitor script: /usr/local/bin/amneziawg-monitor.sh
[SETUP] - Cron job: /etc/cron.d/amneziawg-monitor
[SETUP] - Container logs: docker logs amneziawg
[SETUP] - .env file configured with WG_ENDPOINT and obfuscation values
[SETUP] Output peer configuration...
[Interface]
PrivateKey = <client_private_key>
Address = 10.100.0.2/32
DNS = 9.9.9.9,149.112.112.112
Jc = 3
Jmin = 1
Jmax = 50
S1 = 124
S2 = 52
H1 = 7799
H2 = 16627
H3 = 7319
H4 = 10232

[Peer]
PublicKey = <server_public_key>
PresharedKey = <preshared_key>
Endpoint = <external_ip>:13440
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

---

## Important Notes

* To completely regenerate the VPN configuration, you can delete the contents of `./config`. On the next container launch, it will create new keys and configs.
* Make sure the UDP port (`WG_PORT`) is open on the router/firewall for client connections.
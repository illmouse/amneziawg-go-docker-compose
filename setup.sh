#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[SETUP]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Random number generation functions
get_random_int() {
    local min=$1
    local max=$2
    echo $((min + RANDOM % (max - min)))
}

get_random_junk_size() {
    get_random_int 15 150
}

get_random_header() {
    get_random_int 1000000000 2147483647
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "Please run as root or with sudo"
    exit 1
fi

# Check required files exist
if [ ! -f "./scripts/amneziawg-monitor.sh" ]; then
    error "amneziawg-monitor.sh not found in ./scripts/ directory"
    exit 1
fi

if [ ! -f "./cron/amneziawg-monitor" ]; then
    error "amneziawg-monitor file not found in ./cron/ directory"
    exit 1
fi

if [ ! -f "./docker-compose.yaml" ]; then
    error "docker-compose.yaml not found in current directory"
    exit 1
fi

# Step 0: Configure IP forwarding
log "Configuring IP forwarding in sysctl..."
if grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    log "IP forwarding already enabled in sysctl.conf"
else
    # Remove any existing net.ipv4.ip_forward line
    grep -v "^net.ipv4.ip_forward" /etc/sysctl.conf > /tmp/sysctl.conf.tmp || true
    mv /tmp/sysctl.conf.tmp /etc/sysctl.conf
    
    # Add the setting
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    log "Added net.ipv4.ip_forward=1 to /etc/sysctl.conf"
fi

# Apply sysctl settings
log "Applying sysctl settings..."
if sysctl --system > /dev/null 2>&1; then
    log "Sysctl settings applied successfully"
else
    # Fallback to direct sysctl command
    sysctl -p /etc/sysctl.conf > /dev/null 2>&1 || true
    warn "Used fallback method to apply sysctl settings"
fi

# Verify IP forwarding is enabled
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" -eq 1 ]; then
    log "IP forwarding is enabled (net.ipv4.ip_forward=1)"
else
    warn "IP forwarding is not enabled. Attempting to enable temporarily..."
    echo 1 > /proc/sys/net/ipv4/ip_forward
    if [ "$(cat /proc/sys/net/ipv4/ip_forward)" -eq 1 ]; then
        log "Temporarily enabled IP forwarding"
    else
        error "Failed to enable IP forwarding. WireGuard may not work properly."
    fi
fi

# Step 1: Handle .env file
if [ ! -f "./.env" ]; then
    log "Creating .env file with generated obfuscation values"
    
    # Generate random values
    JC=$(get_random_int 3 10)
    JMIN=50
    JMAX=1000
    S1=$(get_random_junk_size)
    S2=$(get_random_junk_size)
    H1=$(get_random_header)
    H2=$(get_random_header)
    H3=$(get_random_header)
    H4=$(get_random_header)
    
    if [ -f "./.env.example" ]; then
        # Copy example and replace values
        cp ./.env.example ./.env.tmp
        
        # Update or add the generated values
        for var in JC JMIN JMAX S1 S2 H1 H2 H3 H4; do
            value="${!var}"
            if grep -q "^$var=" ./.env.tmp; then
                # Replace existing value
                sed -i "s/^$var=.*/$var=$value/" ./.env.tmp
            else
                # Add new line
                echo "$var=$value" >> ./.env.tmp
            fi
        done
        
        mv ./.env.tmp ./.env
    else
        warn ".env.example not found, creating basic .env file with generated values"
        cat > ./.env << EOF
WG_PORT=13440
WG_ENDPOINT=
JC=$JC
JMIN=$JMIN
JMAX=$JMAX
S1=$S1
S2=$S2
H1=$H1
H2=$H2
H3=$H3
H4=$H4
EOF
    fi
    
    log "Generated obfuscation values:"
    log "  JC=$JC, JMIN=$JMIN, JMAX=$JMAX"
    log "  S1=$S1, S2=$S2"
    log "  H1=$H1, H2=$H2, H3=$H3, H4=$H4"
else
    log ".env file already exists, using existing values"
fi

# Check if WG_ENDPOINT is empty or not set
if grep -q "WG_ENDPOINT=\"\"\|WG_ENDPOINT=''\|^WG_ENDPOINT=\$" ./.env || ! grep -q "^WG_ENDPOINT=" ./.env; then
    warn "WG_ENDPOINT is not set or empty in .env file"
    echo "Please enter your server's public IP address or domain name:"
    read -r user_endpoint
    
    # Remove existing WG_ENDPOINT line if it exists
    grep -v "^WG_ENDPOINT=" ./.env > ./.env.tmp || true
    mv ./.env.tmp ./.env
    
    # Add the new WG_ENDPOINT
    echo "WG_ENDPOINT=$user_endpoint" >> ./.env
    log "WG_ENDPOINT has been set to: $user_endpoint"
fi

# Step 2: Copy monitor script
log "Copying amneziawg-monitor.sh to /usr/local/bin/"
cp ./scripts/amneziawg-monitor.sh /usr/local/bin/amneziawg-monitor.sh
chmod +x /usr/local/bin/amneziawg-monitor.sh

# Step 3: Copy cron file
log "Copying amneziawg-monitor to /etc/cron.d/"
cp ./cron/amneziawg-monitor /etc/cron.d/

# Step 4: Ensure proper permissions for cron file
chmod 644 /etc/cron.d/amneziawg-monitor

# Step 5: Make entrypoint executable
log "Making entrypoint.sh executable"
chmod +x ./entrypoint.sh

# Step 6: Start Docker Compose
log "Starting Docker Compose from current directory"
docker compose up -d

# Step 7: Wait a moment for container to start
log "Waiting for container to initialize..."
sleep 10

# Step 8: Test the monitor script
log "Testing monitor script..."
if /usr/local/bin/amneziawg-monitor.sh; then
    log "Monitor script executed successfully"
else
    warn "Monitor script had issues (this might be normal if container is still starting)"
fi

# Step 9: Show status
log "Checking container status..."
docker ps --filter "name=amneziawg"

log "Setup complete!"
log "- IP forwarding configured in /etc/sysctl.conf"
log "- Monitor script: /usr/local/bin/amneziawg-monitor.sh"
log "- Cron job: /etc/cron.d/amneziawg-monitor"
log "- Container logs: docker logs amneziawg"
log "- .env file configured with WG_ENDPOINT and obfuscation values"

# Step 10: Output perr configuration
log "Output peer configuration..."
cat ./config/peer.conf

#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[SETUP]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Random number generation functions
get_random_int() {
    local min=$1
    local max=$2
    echo $((min + RANDOM % (max - min)))
}

get_random_junk_size() {
    get_random_int 15 150
}

get_random_header() {
    get_random_int 1000000000 2147483647
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "Please run as root or with sudo"
    exit 1
fi

# Check required files exist
if [ ! -f "./scripts/amneziawg-monitor.sh" ]; then
    error "amneziawg-monitor.sh not found in ./scripts/ directory"
    exit 1
fi

if [ ! -f "./cron/amneziawg-monitor" ]; then
    error "amneziawg-monitor file not found in ./cron/ directory"
    exit 1
fi

if [ ! -f "./docker-compose.yaml" ]; then
    error "docker-compose.yaml not found in current directory"
    exit 1
fi

# Step 0: Configure IP forwarding
log "Configuring IP forwarding in sysctl..."
if grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    log "IP forwarding already enabled in sysctl.conf"
else
    # Remove any existing net.ipv4.ip_forward line
    grep -v "^net.ipv4.ip_forward" /etc/sysctl.conf > /tmp/sysctl.conf.tmp || true
    mv /tmp/sysctl.conf.tmp /etc/sysctl.conf
    
    # Add the setting
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    log "Added net.ipv4.ip_forward=1 to /etc/sysctl.conf"
fi

# Apply sysctl settings
log "Applying sysctl settings..."
if sysctl --system > /dev/null 2>&1; then
    log "Sysctl settings applied successfully"
else
    # Fallback to direct sysctl command
    sysctl -p /etc/sysctl.conf > /dev/null 2>&1 || true
    warn "Used fallback method to apply sysctl settings"
fi

# Verify IP forwarding is enabled
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" -eq 1 ]; then
    log "IP forwarding is enabled (net.ipv4.ip_forward=1)"
else
    warn "IP forwarding is not enabled. Attempting to enable temporarily..."
    echo 1 > /proc/sys/net/ipv4/ip_forward
    if [ "$(cat /proc/sys/net/ipv4/ip_forward)" -eq 1 ]; then
        log "Temporarily enabled IP forwarding"
    else
        error "Failed to enable IP forwarding. WireGuard may not work properly."
    fi
fi

# Step 1: Handle .env file
if [ ! -f "./.env" ]; then
    log "Creating .env file with generated obfuscation values"
    
    # Generate random values
    JC=$(get_random_int 3 10)
    JMIN=1
    JMAX=50
    S1=$(get_random_junk_size)
    S2=$(get_random_junk_size)
    H1=$(get_random_header)
    H2=$(get_random_header)
    H3=$(get_random_header)
    H4=$(get_random_header)
    
    if [ -f "./.env.example" ]; then
        # Use env.example as template and replace values in place
        cp ./.env.example ./.env
        
        # Update the generated values in the new .env file
        sed -i "s/^JC=.*/JC=$JC/" ./.env
        sed -i "s/^JMIN=.*/JMIN=$JMIN/" ./.env
        sed -i "s/^JMAX=.*/JMAX=$JMAX/" ./.env
        sed -i "s/^S1=.*/S1=$S1/" ./.env
        sed -i "s/^S2=.*/S2=$S2/" ./.env
        sed -i "s/^H1=.*/H1=$H1/" ./.env
        sed -i "s/^H2=.*/H2=$H2/" ./.env
        sed -i "s/^H3=.*/H3=$H3/" ./.env
        sed -i "s/^H4=.*/H4=$H4/" ./.env
        
    else
        warn ".env.example not found, creating basic .env file with generated values"
        cat > ./.env << EOF
WG_PORT=13440
WG_ENDPOINT=
JC=$JC
JMIN=$JMIN
JMAX=$JMAX
S1=$S1
S2=$S2
H1=$H1
H2=$H2
H3=$H3
H4=$H4
EOF
    fi
    
    log "Generated obfuscation values:"
    log "  JC=$JC, JMIN=$JMIN, JMAX=$JMAX"
    log "  S1=$S1, S2=$S2"
    log "  H1=$H1, H2=$H2, H3=$H3, H4=$H4"
else
    log ".env file already exists, using existing values"
fi

# Check if WG_ENDPOINT is empty or not set
if grep -q "WG_ENDPOINT=\"\"\|WG_ENDPOINT=''\|^WG_ENDPOINT=\$" ./.env || ! grep -q "^WG_ENDPOINT=" ./.env; then
    warn "WG_ENDPOINT is not set or empty in .env file"
    log "Detecting public IP address..."
    
    # Try to get public IP using ifconfig.me
    if PUBLIC_IP=$(curl -s -m 10 ifconfig.me); then
        log "Detected public IP: $PUBLIC_IP"
        user_endpoint="$PUBLIC_IP"
    else
        error "Failed to detect public IP automatically"
        echo "Please enter your server's public IP address or domain name:"
        read -r user_endpoint
    fi
    
    # Remove existing WG_ENDPOINT line if it exists
    grep -v "^WG_ENDPOINT=" ./.env > ./.env.tmp || true
    mv ./.env.tmp ./.env
    
    # Add the new WG_ENDPOINT
    echo "WG_ENDPOINT=$user_endpoint" >> ./.env
    log "WG_ENDPOINT has been set to: $user_endpoint"
fi

# Step 2: Copy monitor script
log "Copying amneziawg-monitor.sh to /usr/local/bin/"
cp ./scripts/amneziawg-monitor.sh /usr/local/bin/amneziawg-monitor.sh
chmod +x /usr/local/bin/amneziawg-monitor.sh

# Step 3: Copy cron file
log "Copying amneziawg-monitor to /etc/cron.d/"
cp ./cron/amneziawg-monitor /etc/cron.d/

# Step 4: Ensure proper permissions for cron file
chmod 644 /etc/cron.d/amneziawg-monitor

# Step 5: Make entrypoint executable
log "Making entrypoint.sh executable"
chmod +x ./entrypoint.sh

# Step 6: Start Docker Compose
log "Starting Docker Compose from current directory"
docker compose up -d

# Step 7: Wait a moment for container to start
log "Waiting for container to initialize..."
sleep 10

# Step 8: Test the monitor script
log "Testing monitor script..."
if /usr/local/bin/amneziawg-monitor.sh; then
    log "Monitor script executed successfully"
else
    warn "Monitor script had issues (this might be normal if container is still starting)"
fi

# Step 9: Show status
log "Checking container status..."
docker ps --filter "name=amneziawg"

# Step 10: Output perr configuration
log "Output peer configuration..."
cat ./config/peer.conf

log "Setup complete!"
log "- IP forwarding configured in /etc/sysctl.conf"
log "- Monitor script: /usr/local/bin/amneziawg-monitor.sh"
log "- Cron job: /etc/cron.d/amneziawg-monitor"
log "- Container logs: docker logs amneziawg"
log "- .env file configured with WG_ENDPOINT and obfuscation values"

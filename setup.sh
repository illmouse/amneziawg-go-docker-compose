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

# Step 1: Copy monitor script
log "Copying amneziawg-monitor.sh to /usr/local/bin/"
cp ./scripts/amneziawg-monitor.sh /usr/local/bin/amneziawg-monitor.sh
chmod +x /usr/local/bin/amneziawg-monitor.sh

# Step 2: Copy cron file
log "Copying amneziawg-monitor to /etc/cron.d/"
cp ./cron/amneziawg-monitor /etc/cron.d/

# Step 3: Ensure proper permissions for cron file
chmod 644 /etc/cron.d/amneziawg-monitor

# Step 5: Start Docker Compose
log "Starting Docker Compose from current directory"
cd ..
docker-compose up -d

# Step 6: Wait a moment for container to start
log "Waiting for container to initialize..."
sleep 10

# Step 7: Test the monitor script
log "Testing monitor script..."
if /usr/local/bin/amneziawg-monitor.sh; then
    log "Monitor script executed successfully"
else
    warn "Monitor script had issues (this might be normal if container is still starting)"
fi

# Step 8: Show status
log "Checking container status..."
docker ps --filter "name=amneziawg"

log "Setup complete!"
log "- Monitor script: /usr/local/bin/amneziawg-monitor.sh"
log "- Cron job: /etc/cron.d/amneziawg-monitor"
log "- Container logs: docker logs amneziawg"
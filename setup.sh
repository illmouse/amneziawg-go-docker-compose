#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

main() {
    log "Starting AmneziaWG setup..."

    chmod +x "$SCRIPT_DIR"/scripts/*.sh
    
    # Step 1: Install Docker and Docker Compose
    if ! "$SCRIPT_DIR/scripts/install-docker.sh"; then
        error "Docker installation failed"
        exit 1
    fi
    
    # Step 2: Configure system settings
    if ! "$SCRIPT_DIR/scripts/configure-system.sh"; then
        error "System configuration failed"
        exit 1
    fi
    
    # Step 3: Setup environment
    if ! "$SCRIPT_DIR/scripts/setup-env.sh"; then
        error "Environment setup failed"
        exit 1
    fi
    
    # Step 4: Deploy monitoring
    if ! "$SCRIPT_DIR/scripts/deploy-monitoring.sh"; then
        error "Monitoring deployment failed"
        exit 1
    fi
    
    # Step 5: Start services
    if ! "$SCRIPT_DIR/scripts/start-services.sh"; then
        error "Service startup failed"
        exit 1
    fi
    
    log "Setup complete!"
    log "- IP forwarding configured in /etc/sysctl.conf"
    log "- Monitor script: /usr/local/bin/amneziawg-monitor.sh"
    log "- Cron job: /etc/cron.d/amneziawg-monitor"
    log "- Container logs: docker logs amneziawg"
    log "- .env file configured with WG_ENDPOINT and obfuscation values"
}

main "$@"
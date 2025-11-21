#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/scripts/functions.sh"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "Please run as root or with sudo"
    exit 1
fi

# Check if .env exists and ask for overwrite
if [ -f ".env" ]; then
    echo ""
    warn ".env file already exists!"
    echo -n "Overwrite .env with new configuration? (y/n, default n): "
    read -r overwrite_choice
    case "$overwrite_choice" in
        y|Y|yes|Yes|YES)
            log "Overwriting existing .env file"
            ;;
        n|N|no|No|NO|"")
            log "Exiting without overwriting .env"
            exit 0
            ;;
        *)
            log "Invalid choice, defaulting to no overwrite"
            exit 0
            ;;
    esac
fi

prompt_user

fix_permissions "$SCRIPT_DIR"

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

# Step 4: Start services
if ! "$SCRIPT_DIR/scripts/start-services.sh"; then
    error "Service startup failed"
    exit 1
fi

log "Setup complete!"
log "- IP forwarding configured in /etc/sysctl.conf"
log "- Container logs: docker logs amneziawg"
log "- .env file configured with WG_ENDPOINT and obfuscation values"
if [ "$WG_MODE" = "client" ]; then
    log "- Tunnel monitoring enabled (client mode)"
else
    log "- Tunnel monitoring disabled (server mode)"
fi

#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR

source "$SCRIPT_DIR/scripts/functions.sh"
source "$SCRIPT_DIR/entrypoint/lib/env.sh"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "Please run as root or with sudo"
    exit 1
fi

fix_permissions "$SCRIPT_DIR"/scripts
# fix_permissions "$SCRIPT_DIR"/entrypoint

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

# Step 3: Create .env file
if ! "$SCRIPT_DIR/scripts/create-env-file.sh"; then
    error "Environment setup failed"
    exit 1
fi

# Step 4: Setup logrotate for logs
if ! "$SCRIPT_DIR/scripts/logrotate.sh"; then
    error "Logrotate setup failed"
    exit 1
fi

# Step 5: Start services
start_services

log "Setup complete!"

#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/functions.sh"

start_services() {
    log "Starting services..."
    
    local project_dir="$(dirname "$SCRIPT_DIR")"
    
    # Start Docker Compose
    log "Starting Docker Compose from current directory"
    cd "$project_dir" && docker compose up -d
    
    # Wait a moment for container to start
    log "Waiting for container to initialize..."
    sleep 10
    
    # Test the monitor script
    log "Testing monitor script..."
    if /usr/local/bin/amneziawg-monitor.sh; then
        log "Monitor script executed successfully"
    else
        warn "Monitor script had issues (this might be normal if container is still starting)"
    fi
    
    # Show status
    log "Checking container status..."
    docker ps --filter "name=amneziawg"
    
    # Output peer configuration
    log "Output peer configuration..."
    if [ -f "$project_dir/config/peer.conf" ]; then
        cat "$project_dir/config/peer.conf"
    else
        warn "Peer configuration not found yet, it may take a moment to generate"
    fi
    
    return 0
}

start_services
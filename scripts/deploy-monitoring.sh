#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/functions.sh"

deploy_monitoring() {
    log "Deploying monitoring..."
    
    local project_dir="$(dirname "$SCRIPT_DIR")"
    
    # Check required files
    if ! check_required_files "$SCRIPT_DIR"; then
        return 1
    fi
    
    # Copy monitor script
    log "Copying amneziawg-monitor.sh to /usr/local/bin/"
    cp "$SCRIPT_DIR/amneziawg-monitor.sh" /usr/local/bin/amneziawg-monitor.sh
    chmod +x /usr/local/bin/amneziawg-monitor.sh
    
    # Copy cron file
    log "Copying amneziawg-monitor to /etc/cron.d/"
    cp "$project_dir/cron/amneziawg-monitor" /etc/cron.d/
    
    # Ensure proper permissions for cron file
    chmod 644 /etc/cron.d/amneziawg-monitor
    
    return 0
}

deploy_monitoring
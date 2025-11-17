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
    
    # Skip deploying the old monitoring system since we're using the new tunnel monitor
    log "Skipping deployment of old monitoring system (using new tunnel monitor in container)"
    
    return 0
}

deploy_monitoring
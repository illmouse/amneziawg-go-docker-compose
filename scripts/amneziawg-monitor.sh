#!/bin/bash

CONTAINER_NAME="amneziawg"
LOG_FILE="/var/log/amneziawg-monitor.log"

log() {
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*" >> "$LOG_FILE"
}

check_container_health() {
    # Check if container exists
    if ! docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
        log "Container $CONTAINER_NAME does not exist"
        return 1
    fi
    
    # Check if container is running
    if [ "$(docker inspect "$CONTAINER_NAME" --format='{{.State.Running}}')" != "true" ]; then
        log "Container $CONTAINER_NAME is not running"
        return 1
    fi
    
    # Check health status if healthcheck is configured
    local health_status=$(docker inspect "$CONTAINER_NAME" --format='{{.State.Health.Status}}' 2>/dev/null)
    if [ -n "$health_status" ] && [ "$health_status" = "unhealthy" ]; then
        log "Container $CONTAINER_NAME is unhealthy"
        return 1
    fi
    
    # Check if WireGuard port is responsive
    local port=$(docker exec "$CONTAINER_NAME" sh -c 'echo $WG_PORT 2>/dev/null || echo 13440' 2>/dev/null)
    if ! nc -z localhost "${port:-13440}" 2>/dev/null; then
        log "WireGuard port ${port:-13440} is not responsive"
        return 1
    fi
    
    return 0
}

# Perform single check
if ! check_container_health; then
    log "Restarting container $CONTAINER_NAME..."
    docker restart "$CONTAINER_NAME"
fi
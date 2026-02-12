#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/functions.sh"

LOG_DIR="${SCRIPT_DIR}/logs"
CONFIG_NAME="app-$(basename "$SCRIPT_DIR")"
LOGROTATE_CONFIG="/etc/logrotate.d/${CONFIG_NAME}"

# Create log directory if needed
if [[ ! -d "$LOG_DIR" ]]; then
    mkdir -p "$LOG_DIR"
    log "Created log directory: $LOG_DIR"
fi

# Create config
cat > "$LOGROTATE_CONFIG" << EOF
${LOG_DIR}/*.*
${LOG_DIR}/*/*.*
${LOG_DIR}/*/*/*.* {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
    dateext
    dateformat -%Y-%m-%d
    maxage 30
}
EOF

log "Config created: $LOGROTATE_CONFIG"

# Test config
if logrotate -d "$LOGROTATE_CONFIG" > /dev/null 2>&1; then
    log "Config test: OK"
else
    error "Config test: FAILED"
    exit 1
fi

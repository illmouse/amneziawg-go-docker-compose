#!/bin/bash

CURRENT_DIR=$(pwd)
LOG_DIR="${CURRENT_DIR}/logs"
CONFIG_NAME="app-$(basename "$CURRENT_DIR")"
LOGROTATE_CONFIG="/etc/logrotate.d/${CONFIG_NAME}"

# Check root
if [[ $EUID -ne 0 ]]; then
    echo "Error: Run with sudo"
    exit 1
fi

# Create log directory if needed
if [[ ! -d "$LOG_DIR" ]]; then
    mkdir -p "$LOG_DIR"
    echo "Created log directory: $LOG_DIR"
fi

# Create config
cat > "$LOGROTATE_CONFIG" << EOF
${LOG_DIR}/*.log
${LOG_DIR}/*/*.log
${LOG_DIR}/*/*/*.log {
    daily
    rotate 30
    compress
    delaycompress
    copytruncate
    missingok
}
EOF

echo "Config created: $LOGROTATE_CONFIG"

# Test config
if logrotate -d "$LOGROTATE_CONFIG" > /dev/null 2>&1; then
    echo "Config test: OK"
else
    echo "Config test: FAILED"
    exit 1
fi
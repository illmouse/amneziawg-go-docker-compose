#!/bin/bash
set -eu

. /entrypoint/lib/env.sh
. /entrypoint/lib/functions.sh

LOGROTATE_CONF="/etc/logrotate.d/amneziawg"
LOGROTATE_STATE="/var/log/amneziawg/logrotate.state"

# Write logrotate config with values from environment
cat > "$LOGROTATE_CONF" << EOF
/var/log/amneziawg/*.log
/var/log/3proxy/*.log {
    rotate ${LOGROTATE_ROTATE}
    maxage ${LOGROTATE_MAXAGE}
    daily
    missingok
    compress
    delaycompress
    notifempty
    copytruncate
    dateext
    dateformat -%Y-%m-%d
}
EOF

info "Log rotation configured (rotate=${LOGROTATE_ROTATE}, maxage=${LOGROTATE_MAXAGE}d, interval=${LOGROTATE_INTERVAL}s)"

while true; do
    sleep "$LOGROTATE_INTERVAL"
    debug "Running logrotate..."
    if logrotate --state "$LOGROTATE_STATE" "$LOGROTATE_CONF" 2>&1 | tee -a "$WG_LOGFILE"; then
        debug "Logrotate completed"
    else
        warn "Logrotate exited with non-zero status"
    fi
done

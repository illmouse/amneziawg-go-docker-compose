#!/bin/bash
set -eu

. /entrypoint/functions.sh
. /entrypoint/env.sh

# Default log file for Squid
: "${SQUID_LOGFILE:=/var/log/amneziawg/squid.log}"

start_squid() {
    if [ "${SQUID_ENABLE:-false}" = "true" ]; then
        info "🦑 Starting Squid proxy on port ${SQUID_PORT} (logs: $SQUID_LOGFILE)..."

        # Ensure log directory exists
        mkdir -p "$(dirname "$SQUID_LOGFILE")"

        # Start Squid in background, redirecting stdout/stderr to log file
        squid -N -d 1 -f /etc/squid/squid.conf >> "$SQUID_LOGFILE" 2>&1 &

        success "Squid proxy started (check $SQUID_LOGFILE for details)"
    else
        info "Squid proxy disabled"
    fi
}
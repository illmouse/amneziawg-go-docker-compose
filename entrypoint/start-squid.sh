#!/bin/bash
set -eu

. /entrypoint/functions.sh
. /entrypoint/env.sh

start_squid() {
    if [ "${SQUID_ENABLED:-false}" = "true" ]; then
        info "🦑 Starting Squid proxy on port ${SQUID_PORT}..."
        # Start Squid service in background (Alpine: service not used, just run squid)
        squid -N -d 1 -f /etc/squid/squid.conf &
        success "Squid proxy started"
    else
        info "Squid proxy disabled"
    fi
}

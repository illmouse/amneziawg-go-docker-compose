#!/bin/bash
set -eu

# Function to setup proxy
proxy_setup() {
    info "Setting up proxy..."

    PROXY_CONF_DIR="/etc/3proxy"

    mkdir -p "$PROXY_LOG_DIR" /var/lib/3proxy

    chown -R 3proxy:3proxy "$PROXY_LOG_DIR" /var/lib/3proxy 2>/dev/null || true
    chmod 755 "$PROXY_LOG_DIR" /var/lib/3proxy

    cat > "$PROXY_CONF_DIR/3proxy.cfg" << EOF
# daemon
nserver 9.9.9.9
nserver 149.112.112.112

maxconn 100
timeouts 1 5 30 60 180 1800 15 60

# Logging
log ${PROXY_LOG_DIR}/3proxy.log D
logformat "- %y-%m-%d %H:%M:%S %U %C:%c %R:%r %O %I %T"

# No authentication
auth none

# HTTP proxy
proxy -p${PROXY_PORT_HTTP}

# SOCKS5 proxy
socks -p${PROXY_PORT_SOCKS5}

# chroot /var/lib/3proxy
# user 3proxy:3proxy
EOF

    success "Proxy configuration created for ports HTTP: ${PROXY_PORT_HTTP} SOCKS5: ${PROXY_PORT_SOCKS5}"
}

# Function to check a proxy port
proxy_check() {
    local PORT=$1
    local TYPE=$2

    if netstat -tuln | grep -q ":${PORT} "; then
        success "${TYPE} proxy is listening on port ${PORT}"

        debug "${TYPE} proxy listening addresses:"
        netstat -tuln | grep ":${PORT}" | while read -r line; do
            debug "  $line"
        done
    else
        error "${TYPE} proxy is NOT listening on port ${PORT}"
    fi
}

# Function to start proxy
proxy_start() {
    if [ "$PROXY_ENABLED" != "true" ]; then
        debug "Proxy is disabled, skipping..."
        return
    fi

    debug "Starting proxy..."

    pkill 3proxy 2>/dev/null || true
    sleep 2

    debug "Starting proxy process..."
    3proxy $PROXY_CONF_DIR/3proxy.cfg &
    PROXY_PID=$!

    sleep 3

    if kill -0 $PROXY_PID 2>/dev/null; then
        success "Proxy running (PID: $PROXY_PID)"

        proxy_check $PROXY_PORT_HTTP "HTTP"
        proxy_check $PROXY_PORT_SOCKS5 "SOCKS5"
    else
        error "Proxy failed to start"
    fi
}

# Setup and start proxy if enabled
if [ "$PROXY_ENABLED" = "true" ]; then
    info "Starting proxy"
    proxy_setup
    proxy_start
else
    debug "Proxy disabled"
fi

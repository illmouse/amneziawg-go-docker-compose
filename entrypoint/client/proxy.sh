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
nserver 9.9.9.9
nserver 149.112.112.112

nscache 65536
stacksize 262144

maxconn 80000
timeouts 1 5 15 30 60 300 5 30

# Logging
log ${PROXY_LOG_DIR}/3proxy.log D
logformat "L%C - %U [%d/%o/%Y:%H:%M:%S %z] ""%T"" %E %I %O %N/%R:%r"
rotate 0

# No authentication
auth none

# HTTP proxy
proxy -n -p${PROXY_PORT_HTTP}

# SOCKS5 proxy
socks -n -p${PROXY_PORT_SOCKS5}

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

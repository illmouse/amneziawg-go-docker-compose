#!/bin/bash
set -eu

# Function to setup proxy
proxy_setup() {
    debug "Setting up proxy..."

    if [ "$PROXY_CUSTOM_CONFIG" = "true" ]; then
        debug "Using custom configuration which should be provided by mounting it to $PROXY_CONF_DIR/3proxy.cfg"
        debug "If no configuration is mounted - stock configuration of 3proxy is used instead and proxy will not work as expected."
        return
    fi

    debug "Custom configuration of 3proxy disabled. Using built-in configuration."

    PROXY_CONF_DIR="/etc/3proxy"

    mkdir -p "$PROXY_LOG_DIR" /var/lib/3proxy

    chown -R 3proxy:3proxy "$PROXY_LOG_DIR" /var/lib/3proxy 2>/dev/null || true
    chmod 755 "$PROXY_LOG_DIR" /var/lib/3proxy

    {
    echo "nserver 9.9.9.9"
    echo "nserver 149.112.112.112"
    echo ""
    echo "nscache 65536"
    echo "stacksize 262144"
    echo ""
    echo "maxconn 80000"
    echo "timeouts 1 5 15 30 60 300 5 30"
    echo ""
    echo "# Logging"
    echo "log ${PROXY_LOG_DIR}/3proxy.log D"
    echo 'logformat "L%C - %U [%d/%o/%Y:%H:%M:%S %z] \"%T\" %E %I %O %N/%R:%r"'
    echo "rotate 0"
    echo ""

    ########################################
    # Authentication
    ########################################

    # Build user list string if any auth is enabled
    USER_LIST=""

    if [ "$PROXY_AUTH_SOCKS5_ENABLED" = "true" ]; then
        SOCKS_HASH="$(hash_pass "$PROXY_AUTH_SOCKS5_PASSWORD")"
        USER_LIST+=" ${PROXY_AUTH_SOCKS5_USER}:CR:${SOCKS_HASH}"
    fi

    if [ "$PROXY_AUTH_HTTP_ENABLED" = "true" ]; then
        HTTP_HASH="$(hash_pass "$PROXY_AUTH_HTTP_PASSWORD")"
        USER_LIST+=" ${PROXY_AUTH_HTTP_USER}:CR:${HTTP_HASH}"
    fi

    if [ -n "$USER_LIST" ]; then
        # Trim leading space
        USER_LIST="${USER_LIST#" "}"
        echo "auth strong"
        echo "users $USER_LIST"
    else
        echo "auth none"
    fi

    echo ""

    ########################################
    # HTTP Proxy
    ########################################

    if [ "$PROXY_HTTP_ENABLED" = "true" ]; then
        echo "proxy -n -p${PROXY_PORT_HTTP}"
    fi

    echo ""

    ########################################
    # SOCKS5 Proxy
    ########################################

    if [ "$PROXY_SOCKS5_ENABLED" = "true" ]; then
        echo "socks -n -p${PROXY_PORT_SOCKS5}"
    fi

    } > "$PROXY_CONF_DIR/3proxy.cfg"

#     cat > "$PROXY_CONF_DIR/3proxy.cfg" << EOF
# nserver 9.9.9.9
# nserver 149.112.112.112

# nscache 65536
# stacksize 262144

# maxconn 80000
# timeouts 1 5 15 30 60 300 5 30

# # Logging
# log ${PROXY_LOG_DIR}/3proxy.log D
# logformat "L%C - %U [%d/%o/%Y:%H:%M:%S %z] ""%T"" %E %I %O %N/%R:%r"
# rotate 0

# # No authentication
# auth none

# # HTTP proxy
# proxy -n -p${PROXY_PORT_HTTP}

# # SOCKS5 proxy
# socks -n -p${PROXY_PORT_SOCKS5}

# EOF

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
    info "Starting proxy..."

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
if [ "$PROXY_SOCKS5_ENABLED" = "true" ] || [ "$PROXY_HTTP_ENABLED" = "true" ]; then
    if [ "$PROXY_CUSTOM_CONFIG" = "false" ]; then
        proxy_setup
    else
        info "Custom configuration of 3proxy disabled. Using built-in configuration."
    fi
    proxy_start
else
    debug "Proxy disabled"
fi

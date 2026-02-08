# Function to setup Squid proxy
setup_squid() {
    info "${SQUID_EMOJI} Setting up Squid proxy..."
    
    # Install Squid
    if ! command -v squid >/dev/null 2>&1; then
        info "Installing Squid..."
        if ! apk add --no-cache squid; then
            error "Failed to install Squid"
        fi
        success "Squid installed successfully"
    else
        info "Squid already installed"
    fi
    
    # Create Squid configuration directories
    SQUID_CONF_DIR="/etc/squid"
    SQUID_CACHE_DIR="/var/cache/squid"
    SQUID_LOG_DIR="/var/log/amneziawg/squid"
    
    mkdir -p "$SQUID_CONF_DIR" "$SQUID_CACHE_DIR" "$SQUID_LOG_DIR"
    
    # Fix permissions
    chown -R squid:squid "$SQUID_CACHE_DIR" "$SQUID_LOG_DIR" 2>/dev/null || true
    chmod 755 "$SQUID_CACHE_DIR" "$SQUID_LOG_DIR"
    
    # Simple Squid config using SQUID_PORT variable
    cat > "$SQUID_CONF_DIR/squid.conf" << SQUID_CONFIG
# Squid proxy configuration
http_port 0.0.0.0:${SQUID_PORT}

# Allow all traffic
http_access allow all

# Cache settings for mixed file sizes
cache_dir ufs /var/cache/squid 5000 16 256
cache_mem 512 MB
maximum_object_size 20 GB

# Performance settings
via on
forwarded_for delete
pipeline_prefetch 2
connect_timeout 45 seconds
read_timeout 1800 seconds
SQUID_CONFIG
    
    # Initialize Squid cache
    info "Initializing Squid cache..."
    if squid -z -N -f /etc/squid/squid.conf; then
        success "Squid cache initialized"
    else
        warn "Squid cache initialization had issues"
    fi
    
    success "Squid proxy configuration created for port ${SQUID_PORT}"
}

# Function to start Squid proxy
start_squid() {
    if [ "$SQUID_ENABLE" != "true" ]; then
        info "${SQUID_EMOJI} Squid proxy is disabled, skipping..."
        return
    fi

    info "${SQUID_EMOJI} Starting Squid proxy..."
    
    # Kill any existing Squid processes first
    pkill squid 2>/dev/null || true
    sleep 2
    
    # Start Squid in foreground and background it
    info "Starting Squid process on port ${SQUID_PORT}..."
    squid -f /etc/squid/squid.conf -N &
    SQUID_PID=$!
    
    # Wait for Squid to start
    sleep 3
    
    if kill -0 $SQUID_PID 2>/dev/null; then
        success "Squid proxy running on port ${SQUID_PORT} (PID: $SQUID_PID)"
        
        # Check if it's listening
        if netstat -tuln | grep -q ":${SQUID_PORT} "; then
            success "Squid is listening on port ${SQUID_PORT}"
            
            # Show listening addresses
            info "Squid listening addresses:"
            netstat -tuln | grep ":${SQUID_PORT}" | while read -r line; do
                info "  $line"
            done
        else
            error "Squid is not listening on port ${SQUID_PORT}"
        fi
    else
        error "Squid failed to start on port ${SQUID_PORT}"
    fi
}
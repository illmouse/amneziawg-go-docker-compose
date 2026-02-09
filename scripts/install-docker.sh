#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/functions.sh"

install_docker() {
    log "Checking Docker installation..."
    
    # Check if Docker is already installed
    if command -v docker >/dev/null 2>&1 && command -v docker compose >/dev/null 2>&1; then
        log "Docker and Docker Compose are already installed"
        return 0
    fi
    
    log "Installing Docker and Docker Compose..."
    
    # Detect distribution
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case $ID in
            ubuntu|debian|linuxmint)
                install_docker_debian
                ;;
            centos|rhel|fedora)
                install_docker_redhat
                ;;
            *)
                warn "Unsupported distribution: $ID - attempting to proceed with existing Docker installation"
                ;;
        esac
    else
        warn "Cannot detect distribution - attempting to proceed with existing Docker installation"
    fi
    
    # Start and enable Docker service
    systemctl enable docker
    systemctl start docker
    
    # Verify Docker installation worked
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        log "Docker and Docker Compose are installed and working"
    else
        warn "Docker installation may have failed, but continuing as Docker might be installed manually"
        # Try to start Docker service if it exists
        if systemctl is-enabled docker >/dev/null 2>&1; then
            systemctl start docker 2>/dev/null || true
        fi
    fi
}

install_docker_debian() {
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

    # Detect base distro for Docker repository
    BASE_ID="$ID"
    CODENAME="$(lsb_release -cs)"    # may be wrong for Linux Mint / LMDE

    # Correct handling for Linux Mint (Ubuntu-based OR LMDE)
    if [ "$ID" = "linuxmint" ]; then
        if [ -n "$UBUNTU_CODENAME" ]; then
            # Ubuntu-based Linux Mint (e.g., Mint 21.x)
            log "Detected Ubuntu-based Linux Mint – using Ubuntu codename '$UBUNTU_CODENAME'"
            BASE_ID="ubuntu"
            CODENAME="$UBUNTU_CODENAME"
        elif [ -n "$DEBIAN_CODENAME" ]; then
            # LMDE (Debian-based)
            log "Detected LMDE – using Debian codename '$DEBIAN_CODENAME'"
            BASE_ID="debian"
            CODENAME="$DEBIAN_CODENAME"
        else
            error "Unable to determine base distro for Linux Mint"
            exit 1
        fi
    fi

    # Correct handling for Ubuntu
    if [ "$ID" = "ubuntu" ]; then
        BASE_ID="ubuntu"
        CODENAME="$UBUNTU_CODENAME"
        log "Detected Ubuntu – using codename '$CODENAME'"
    fi

    # Correct handling for Debian
    if [ "$ID" = "debian" ]; then
        BASE_ID="debian"
        CODENAME="$DEBIAN_CODENAME"
        log "Detected Debian – using codename '$CODENAME'"
    fi

    # Detect architecture
    local dpkg_arch
    dpkg_arch="$(dpkg --print-architecture)"

    # Add Docker GPG key
    curl -fsSL https://download.docker.com/linux/$BASE_ID/gpg \
        | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    # Add correct repository
    echo "deb [arch=$dpkg_arch signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
        https://download.docker.com/linux/$BASE_ID $CODENAME stable" \
        > /etc/apt/sources.list.d/docker.list

    # Install Docker + Compose
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # Install standalone Compose for safety
    curl -SL "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
}



install_docker_redhat() {
    # Install prerequisites
    yum install -y yum-utils device-mapper-persistent-data lvm2

    # Add Docker repository
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

    # Install Docker packages
    yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # Install docker-compose standalone for compatibility
    curl -SL "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
}

install_docker
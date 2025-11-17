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
    if command -v docker >/dev/null 2>&1 && command -v docker-compose >/dev/null 2>&1; then
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
    # Update package index
    apt-get update
    
    # Install prerequisites
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt-get update
    # Install Docker packages
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    # Also install docker-compose standalone for compatibility
    curl -SL "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Install Docker Compose standalone (for compatibility)
    curl -SL "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
}

install_docker_redhat() {
    # Install prerequisites
    yum install -y yum-utils device-mapper-persistent-data lvm2
    
    # Add Docker repository
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    
    # Install Docker
    # Install Docker packages
    yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    # Also install docker-compose standalone for compatibility
    curl -SL "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Install Docker Compose standalone
    curl -SL "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
}

install_docker
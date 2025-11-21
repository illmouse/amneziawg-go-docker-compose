#!/bin/bash
set -eu

# ===============================
# Ensure required packages are installed
# ===============================

install_required_packages() {
    for pkg in $REQUIRED_PKGS; do
        if ! command -v "$pkg" >/dev/null 2>&1; then
            info "🔵 $pkg not found. Installing..."
            if command -v apk >/dev/null 2>&1; then
                apk add --no-cache "$pkg"
            elif command -v apt-get >/dev/null 2>&1; then
                apt-get update && apt-get install -y "$pkg"
            else
                error "Package manager not detected. Please install $pkg manually."
            fi
            success "✅ $pkg installed"
        else
            info "✅ $pkg already installed"
        fi
    done
}

install_required_packages
